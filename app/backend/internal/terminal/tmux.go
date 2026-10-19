package terminal

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Why tmux: the PTY shell used to be a child of archangeld, so it
// inherited archangel.service's sandbox (read-only /etc and /usr via
// ProtectSystem=full, PrivateTmp, the 150M MemoryMax cgroup) and died on
// every service restart. Now the shells live inside a tmux *server* that
// runs under the archangel user's systemd user manager - a different
// cgroup and mount namespace than archangel.service. The WebSocket PTY
// just runs a tmux *client* (a viewer); killing the client or restarting
// archangeld leaves the shells alive and re-attachable.
//
// PrivateTmp hides the default /tmp socket from the other side, so the
// socket is always an explicit path (-S).

// DefaultSocketPath is where the tmux server's socket lives unless config
// says otherwise. It sits in the archangel user's home, which both the
// sandboxed service and the user manager can reach.
const DefaultSocketPath = "/home/archangel/.archangel/tmux.sock"

const defaultSession = "main"

var (
	socketMu   sync.RWMutex
	socketPath = DefaultSocketPath
)

// SetSocketPath overrides the tmux socket path (config: terminal_socket).
// Empty keeps the default.
func SetSocketPath(p string) {
	if p == "" {
		return
	}
	socketMu.Lock()
	defer socketMu.Unlock()
	socketPath = p
}

func getSocketPath() string {
	socketMu.RLock()
	defer socketMu.RUnlock()
	return socketPath
}

// validSessionName bounds what we ever hand to tmux as a session name.
// Notably no ':' or '.', which tmux treats as target separators.
var validSessionName = regexp.MustCompile(`^[A-Za-z0-9_-]{1,32}$`)

// runCmd runs a command (with extra env entries appended to the process
// environment) and returns its stdout; on failure the error includes
// stderr. A package-level var so tests can stub tmux/systemd-run out.
var runCmd = func(ctx context.Context, env []string, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	if len(env) > 0 {
		cmd.Env = append(os.Environ(), env...)
	}
	var out, errBuf bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errBuf
	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(errBuf.String()); msg != "" {
			return out.Bytes(), fmt.Errorf("%w: %s", err, msg)
		}
		return out.Bytes(), err
	}
	return out.Bytes(), nil
}

var (
	lookPath = exec.LookPath
	getUID   = os.Getuid
)

// ---- pure argument builders (unit-tested) ----

func hasSessionArgs(sock string) []string {
	return []string{"-S", sock, "has-session"}
}

func homeDir() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	return "/home/archangel"
}

// startServerArgs: systemd-run arguments that launch the tmux server as a
// transient unit under the *user* manager (so it escapes archangel.service's
// cgroup and namespace). Type=forking because `tmux new-session -d` forks
// the server into the background and exits.
func startServerArgs(sock string) []string {
	return []string{
		"--user", "--quiet", "--collect", "--unit=archangel-tmux",
		"-p", "Type=forking",
		"-E", "HOME=" + homeDir(),
		"--",
		"tmux", "-S", sock, "new-session", "-d", "-s", defaultSession, ";", "set-option", "-g", "status", "off",
	}
}

// userManagerEnv is what systemd-run --user needs to find the user bus when
// we're not inside a login session.
func userManagerEnv(uid int) []string {
	rt := "/run/user/" + strconv.Itoa(uid)
	return []string{
		"XDG_RUNTIME_DIR=" + rt,
		"DBUS_SESSION_BUS_ADDRESS=unix:path=" + rt + "/bus",
	}
}

// clientArgs: the tmux client the PTY runs. -A attaches if the session
// exists, creates it otherwise.
// The trailing set-option hides tmux's status bar - the app shows session
// tabs itself - and also applies to servers started before this existed.
func clientArgs(sock, session string) []string {
	return []string{"-S", sock, "new-session", "-A", "-s", session, ";", "set-option", "-g", "status", "off"}
}

const listFormat = "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}"

func listArgs(sock string) []string {
	return []string{"-S", sock, "list-sessions", "-F", listFormat}
}

// killArgs uses '=' for an exact-name match (tmux otherwise prefix-matches).
func killArgs(sock, name string) []string {
	return []string{"-S", sock, "kill-session", "-t", "=" + name}
}

// ---- server lifecycle ----

var ensureMu sync.Mutex

// ensureServer makes sure a tmux server is running on the socket,
// starting it under the user manager if not. Serialized so concurrent
// first connections don't race to create it.
func ensureServer() error {
	ensureMu.Lock()
	defer ensureMu.Unlock()

	sock := getSocketPath()
	if _, err := lookPath("tmux"); err != nil {
		return fmt.Errorf("tmux is not installed")
	}
	if err := os.MkdirAll(filepath.Dir(sock), 0o700); err != nil {
		return fmt.Errorf("creating socket dir: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if _, err := runCmd(ctx, nil, "tmux", hasSessionArgs(sock)...); err == nil {
		return nil
	}

	if _, err := lookPath("systemd-run"); err != nil {
		return fmt.Errorf("systemd-run is not installed")
	}
	env := userManagerEnv(getUID())
	if _, err := runCmd(ctx, env, "systemd-run", startServerArgs(sock)...); err != nil {
		return fmt.Errorf("starting tmux via systemd-run: %w", err)
	}
	if _, err := runCmd(ctx, nil, "tmux", hasSessionArgs(sock)...); err != nil {
		return fmt.Errorf("tmux server did not come up: %w", err)
	}
	return nil
}

// ---- session listing ----

// SessionInfo is one tmux session as returned by GET /api/v1/terminal/sessions.
type SessionInfo struct {
	Name        string `json:"name"`
	Windows     int    `json:"windows"`
	Attached    int    `json:"attached"`
	CreatedUnix int64  `json:"created_unix"`
}

// parseSessions parses tab-separated list-sessions output; malformed lines
// are skipped.
func parseSessions(out string) []SessionInfo {
	list := []SessionInfo{}
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimRight(line, "\r")
		f := strings.Split(line, "\t")
		if len(f) != 4 || f[0] == "" {
			continue
		}
		w, err1 := strconv.Atoi(f[1])
		a, err2 := strconv.Atoi(f[2])
		c, err3 := strconv.ParseInt(f[3], 10, 64)
		if err1 != nil || err2 != nil || err3 != nil {
			continue
		}
		list = append(list, SessionInfo{Name: f[0], Windows: w, Attached: a, CreatedUnix: c})
	}
	return list
}

// isNoServer reports whether a tmux error just means "no server is running
// (yet)" - an empty session list, not a failure.
func isNoServer(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	return strings.Contains(s, "no server running") ||
		strings.Contains(s, "error connecting to") ||
		strings.Contains(s, "No such file or directory")
}

// SessionsHandler handles GET /api/v1/terminal/sessions
func SessionsHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	out, err := runCmd(ctx, nil, "tmux", listArgs(getSocketPath())...)
	list := []SessionInfo{}
	if err != nil {
		if !isNoServer(err) {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "failed to list sessions: " + err.Error()})
			return
		}
	} else {
		list = parseSessions(string(out))
	}
	writeJSON(w, http.StatusOK, list)
}

// SessionDeleteHandler handles DELETE /api/v1/terminal/sessions/{name}
func SessionDeleteHandler(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if !validSessionName.MatchString(name) {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "invalid session name"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	if _, err := runCmd(ctx, nil, "tmux", killArgs(getSocketPath(), name)...); err != nil {
		status := http.StatusInternalServerError
		if isNoServer(err) || strings.Contains(err.Error(), "can't find session") {
			status = http.StatusNotFound
		}
		writeJSON(w, status, map[string]any{"success": false, "message": "failed to kill session: " + err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "session " + name + " killed"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
