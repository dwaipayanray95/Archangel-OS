// Package terminal bridges a real PTY (pseudo-terminal) shell to a
// WebSocket connection, so the Flutter app gets a genuine interactive
// terminal - not just "run a command, get output back". Shells are hosted
// by a tmux server outside the service sandbox (see tmux.go) so they
// survive reconnects and service restarts. Interactive
// programs (nano, htop, a shell prompt asking y/n) work correctly because
// this is a real PTY, the same mechanism a normal SSH session uses.
package terminal

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"sync/atomic"
	"time"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"

	"github.com/dwaipayanray95/project-archangel/backend/internal/wsproto"
)

const (
	// MaxSessions caps concurrent terminal sessions. This is a single-user
	// tool; a handful of tabs is plenty, and capping this bounds worst-case
	// memory/process usage on a 1GB box.
	MaxSessions = 3

	// maxFrameBytes bounds a single WS message. Terminal I/O frames are
	// small (a few KB of base64 at most); this just guards against a
	// broken or hostile client sending something huge.
	maxFrameBytes = 64 * 1024

	// idleTimeout: a session with no traffic at all for this long is
	// assumed dead and dropped, so it can't sit on one of only
	// MaxSessions slots indefinitely. Refreshed on every frame received.
	idleTimeout = 10 * time.Minute
)

var activeSessions atomic.Int32

// tryAcquireSession atomically checks the session cap and reserves a slot
// in one step - checking activeSessions.Load() and then calling Add(1)
// separately would leave a window where two connections arriving at the
// same instant could both pass the check before either increments,
// letting the count exceed MaxSessions.
func tryAcquireSession() bool {
	for {
		cur := activeSessions.Load()
		if cur >= MaxSessions {
			return false
		}
		if activeSessions.CompareAndSwap(cur, cur+1) {
			return true
		}
	}
}

// sessions tracks every open connection so CloseAll can reach them. This
// exists because WebSocket connections are hijacked out of net/http's
// normal request handling once upgraded - http.Server.Shutdown() is
// documented to NOT wait for or close hijacked connections like these, so
// without this registry a server restart would silently orphan every open
// shell instead of killing it.
var (
	sessionsMu sync.Mutex
	sessions   = map[*websocket.Conn]struct{}{}
)

// CloseAll force-closes every open terminal session. Called from main on
// shutdown, before/alongside http.Server.Shutdown, so in-flight PTY child
// processes get killed and reaped (see the cleanup path in Handler) instead
// of being abandoned when the process exits.
func CloseAll() {
	sessionsMu.Lock()
	defer sessionsMu.Unlock()
	for conn := range sessions {
		_ = conn.Close()
	}
}

var upgrader = websocket.Upgrader{
	// Single-user personal tool behind WireGuard - the origin check that
	// matters (network reachability) is already enforced by the bind
	// address and firewall, not by browser Origin headers.
	CheckOrigin: func(r *http.Request) bool { return true },
}

// Handler serves GET /ws/terminal?session=<name>. The shell runs inside a
// persistent tmux session (see tmux.go); if tmux can't be set up it falls
// back to a plain, temporary login shell.
func Handler(w http.ResponseWriter, r *http.Request) {
	session := r.URL.Query().Get("session")
	if session == "" {
		session = defaultSession
	}
	if !validSessionName.MatchString(session) {
		http.Error(w, "invalid session name (use 1-32 of A-Z a-z 0-9 _ -)", http.StatusBadRequest)
		return
	}

	if !tryAcquireSession() {
		http.Error(w, "too many concurrent terminal sessions", http.StatusServiceUnavailable)
		return
	}
	defer activeSessions.Add(-1)

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("terminal: websocket upgrade failed", "err", err)
		return
	}
	defer conn.Close()

	sessionsMu.Lock()
	sessions[conn] = struct{}{}
	sessionsMu.Unlock()
	defer func() {
		sessionsMu.Lock()
		delete(sessions, conn)
		sessionsMu.Unlock()
	}()

	// Idle sessions shouldn't be able to hold one of only MaxSessions slots
	// forever, and an unbounded frame is a real memory risk on a 1GB box.
	// The deadline is refreshed on every successfully read frame in the main
	// loop below (our protocol uses its own app-level ping/pong JSON frames,
	// not WS control frames, so there's no separate pong handler to wire up).
	conn.SetReadLimit(maxFrameBytes)
	_ = conn.SetReadDeadline(time.Now().Add(idleTimeout))

	var cmd *exec.Cmd
	if err := ensureServer(); err != nil {
		// Same behaviour as before tmux existed: a shell that is a child
		// of this process (sandboxed, dies with the service). Tell the
		// client first so it can show why history/persistence is missing.
		slog.Warn("terminal: persistent sessions unavailable", "err", err)
		sendFrame(conn, wsproto.Frame{
			Type:    wsproto.TypeError,
			Message: fmt.Sprintf("Persistent sessions unavailable (%v), using a temporary shell", err),
		})
		shell := os.Getenv("SHELL")
		if shell == "" {
			shell = "/bin/bash"
		}
		cmd = exec.Command(shell, "-l")
	} else {
		cmd = exec.Command("tmux", clientArgs(getSocketPath(), session)...)
		cmd.Env = append(os.Environ(), "TERM=xterm-256color")
	}

	ptmx, err := pty.Start(cmd)
	if err != nil {
		slog.Error("terminal: failed to start pty", "err", err)
		sendFrame(conn, wsproto.Frame{Type: wsproto.TypeError, Message: "failed to start shell"})
		return
	}
	defer ptmx.Close()

	// Default size; the client sends a "resize" frame right after connecting
	// with its real terminal dimensions.
	_ = pty.Setsize(ptmx, &pty.Winsize{Rows: 24, Cols: 80})

	var writeMu sync.Mutex
	safeSendFrame := func(f wsproto.Frame) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return conn.WriteJSON(f)
	}

	// PTY output -> WebSocket. When the shell itself exits (not just the
	// client disconnecting), ptmx.Read returns EOF here - but that alone
	// doesn't wake the WebSocket read loop below, which is blocked waiting
	// for client input that may never come. Forcing an immediate read
	// deadline makes conn.ReadMessage() return an error (without killing
	// the socket outright) so the main loop reaches the cleanup path and
	// still gets to send the "exit" frame the client is waiting for -
	// closing the connection directly here would race with that send.
	done := make(chan struct{})
	go func() {
		defer close(done)
		buf := make([]byte, 4096)
		for {
			n, err := ptmx.Read(buf)
			if n > 0 {
				frame := wsproto.Frame{
					Type: wsproto.TypeStdout,
					Data: base64.StdEncoding.EncodeToString(buf[:n]),
				}
				if werr := safeSendFrame(frame); werr != nil {
					return
				}
			}
			if err != nil {
				_ = conn.SetReadDeadline(time.Now())
				return
			}
		}
	}()

	// WebSocket input -> PTY
	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			break
		}
		_ = conn.SetReadDeadline(time.Now().Add(idleTimeout))

		var frame wsproto.Frame
		if err := json.Unmarshal(raw, &frame); err != nil {
			continue
		}

		switch frame.Type {
		case wsproto.TypeStdin:
			data, err := base64.StdEncoding.DecodeString(frame.Data)
			if err != nil {
				continue
			}
			if _, err := ptmx.Write(data); err != nil {
				goto cleanup
			}
		case wsproto.TypeResize:
			if frame.Cols > 0 && frame.Rows > 0 {
				_ = pty.Setsize(ptmx, &pty.Winsize{
					Rows: uint16(frame.Rows),
					Cols: uint16(frame.Cols),
				})
			}
		case wsproto.TypePing:
			_ = safeSendFrame(wsproto.Frame{Type: wsproto.TypePong})
		}
	}

cleanup:
	// Kill covers the client-disconnect case (shell may still be running);
	// in tmux mode this kills only the tmux *client* - the session and its
	// shells live on in the tmux server. It's a no-op error (ignored) if the
	// process already exited on its own.
	// Wait is required either way - without it cmd.ProcessState is never
	// populated (exit code would always read as 0) and the child process
	// is never reaped, leaking a zombie process per terminal session.
	_ = cmd.Process.Kill()
	_ = cmd.Wait()
	<-done

	exitCode := 0
	if state := cmd.ProcessState; state != nil {
		exitCode = state.ExitCode()
	}
	_ = safeSendFrame(wsproto.Frame{Type: wsproto.TypeExit, Code: exitCode})
}

func sendFrame(conn *websocket.Conn, f wsproto.Frame) {
	_ = conn.WriteJSON(f)
}
