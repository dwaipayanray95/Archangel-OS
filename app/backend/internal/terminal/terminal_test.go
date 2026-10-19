package terminal

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// TestTryAcquireSessionCapIsHard fires many concurrent acquire attempts at
// once and asserts the count granted never exceeds MaxSessions. This is
// specifically a regression test for a real bug: a naive
// "if Load() >= Max { reject }; Add(1)" check has a window where two
// goroutines can both pass the check before either increments, letting the
// cap slip. tryAcquireSession must check-and-reserve atomically instead.
func TestTryAcquireSessionCapIsHard(t *testing.T) {
	activeSessions.Store(0)
	defer activeSessions.Store(0)

	const attempts = 50
	var wg sync.WaitGroup
	var granted int32Counter

	// A start gate: every goroutine is spun up and parked on the closed
	// channel receive before any of them call tryAcquireSession, so they
	// actually collide on the same instant instead of running one after
	// another - launching goroutines in a plain loop without this very
	// reliably fails to reproduce the race at all (confirmed by hand:
	// the pre-fix naive Load-then-Add version passed 20/20 runs of this
	// test without a start gate).
	start := make(chan struct{})
	wg.Add(attempts)
	for i := 0; i < attempts; i++ {
		go func() {
			defer wg.Done()
			<-start
			if tryAcquireSession() {
				granted.inc()
			}
		}()
	}
	close(start)
	wg.Wait()

	if got := granted.load(); got != MaxSessions {
		t.Fatalf("granted %d sessions concurrently, want exactly %d (MaxSessions)", got, MaxSessions)
	}
	if cur := activeSessions.Load(); cur != MaxSessions {
		t.Fatalf("activeSessions ended at %d, want %d", cur, MaxSessions)
	}
}

// int32Counter is a tiny thread-safe counter, local to this test file - no
// need to pull in a dependency for one counter.
type int32Counter struct {
	mu sync.Mutex
	n  int32
}

func (c *int32Counter) inc() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.n++
}

func (c *int32Counter) load() int32 {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.n
}

func TestValidSessionName(t *testing.T) {
	for _, n := range []string{"main", "a", "work_1-2", "ABCdef0123456789ABCdef0123456789"} {
		if !validSessionName.MatchString(n) {
			t.Errorf("%q should be valid", n)
		}
	}
	for _, n := range []string{"", "has space", "a:b", "a.b", "semi;colon", "$(x)", "-n\nx", "toolong0123456789012345678901234567"} {
		if validSessionName.MatchString(n) {
			t.Errorf("%q should be invalid", n)
		}
	}
}

func TestArgBuilders(t *testing.T) {
	sock := "/home/archangel/.archangel/tmux.sock"
	if got := strings.Join(clientArgs(sock, "work"), " "); got != "-S "+sock+" new-session -A -s work" {
		t.Errorf("clientArgs = %q", got)
	}
	if got := strings.Join(killArgs(sock, "work"), " "); got != "-S "+sock+" kill-session -t =work" {
		t.Errorf("killArgs = %q", got)
	}
	start := strings.Join(startServerArgs(sock), " ")
	for _, want := range []string{"--user", "--collect", "--unit=archangel-tmux", "Type=forking", "-- tmux -S " + sock + " new-session -d -s main"} {
		if !strings.Contains(start, want) {
			t.Errorf("startServerArgs %q missing %q", start, want)
		}
	}
	env := strings.Join(userManagerEnv(1001), " ")
	if env != "XDG_RUNTIME_DIR=/run/user/1001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus" {
		t.Errorf("userManagerEnv = %q", env)
	}
	if l := listArgs(sock); l[len(l)-1] != listFormat || !strings.Contains(listFormat, "\t") {
		t.Errorf("listArgs = %v", l)
	}
}

func TestParseSessions(t *testing.T) {
	out := "main\t2\t1\t1760000000\nwork\t1\t0\t1760000100\nbroken line\nbad\tx\t0\t1\n\n"
	got := parseSessions(out)
	want := []SessionInfo{
		{Name: "main", Windows: 2, Attached: 1, CreatedUnix: 1760000000},
		{Name: "work", Windows: 1, Attached: 0, CreatedUnix: 1760000100},
	}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("parseSessions = %+v", got)
	}
	if got := parseSessions(""); got == nil || len(got) != 0 {
		t.Errorf("empty parse should be empty non-nil slice, got %#v", got)
	}
}

// stubRun swaps runCmd/lookPath for the duration of a test.
func stubRun(t *testing.T, fn func(env []string, name string, args []string) ([]byte, error)) *[]string {
	t.Helper()
	var calls []string
	oldRun, oldLook := runCmd, lookPath
	runCmd = func(_ context.Context, env []string, name string, args ...string) ([]byte, error) {
		calls = append(calls, name+" "+strings.Join(args, " "))
		return fn(env, name, args)
	}
	lookPath = func(string) (string, error) { return "/usr/bin/x", nil }
	t.Cleanup(func() { runCmd, lookPath = oldRun, oldLook })
	return &calls
}

func withSocket(t *testing.T) string {
	t.Helper()
	old := getSocketPath()
	sock := filepath.Join(t.TempDir(), "sub", "tmux.sock")
	SetSocketPath(sock)
	t.Cleanup(func() { SetSocketPath(old) })
	return sock
}

func TestEnsureServerAlreadyRunning(t *testing.T) {
	sock := withSocket(t)
	calls := stubRun(t, func([]string, string, []string) ([]byte, error) { return nil, nil })
	if err := ensureServer(); err != nil {
		t.Fatal(err)
	}
	if len(*calls) != 1 || !strings.Contains((*calls)[0], "has-session") {
		t.Errorf("calls = %v", *calls)
	}
	info, err := os.Stat(filepath.Dir(sock))
	if err != nil || info.Mode().Perm() != 0o700 {
		t.Errorf("socket dir: %v %v", info, err)
	}
}

func TestEnsureServerStartsViaSystemdRun(t *testing.T) {
	withSocket(t)
	started := false
	calls := stubRun(t, func(env []string, name string, args []string) ([]byte, error) {
		if name == "systemd-run" {
			started = true
			if len(env) != 2 || !strings.HasPrefix(env[0], "XDG_RUNTIME_DIR=/run/user/") {
				t.Errorf("env = %v", env)
			}
			return nil, nil
		}
		if !started {
			return nil, errors.New("no server running")
		}
		return nil, nil
	})
	if err := ensureServer(); err != nil {
		t.Fatal(err)
	}
	if len(*calls) != 3 || !strings.HasPrefix((*calls)[1], "systemd-run --user") {
		t.Errorf("calls = %v", *calls)
	}
}

func TestEnsureServerFailureIsReported(t *testing.T) {
	withSocket(t)
	stubRun(t, func(_ []string, name string, _ []string) ([]byte, error) {
		return nil, errors.New("boom")
	})
	if err := ensureServer(); err == nil || !strings.Contains(err.Error(), "systemd-run") {
		t.Errorf("err = %v", err)
	}
}

func TestSessionsHandler(t *testing.T) {
	withSocket(t)
	stubRun(t, func([]string, string, []string) ([]byte, error) {
		return []byte("main\t1\t1\t1760000000\n"), nil
	})
	rec := httptest.NewRecorder()
	SessionsHandler(rec, httptest.NewRequest("GET", "/api/v1/terminal/sessions", nil))
	var got []SessionInfo
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil || len(got) != 1 || got[0].Name != "main" {
		t.Errorf("body = %s (%v)", rec.Body.String(), err)
	}
	if !strings.Contains(rec.Body.String(), `"created_unix":1760000000`) {
		t.Errorf("body = %s", rec.Body.String())
	}

	stubRun(t, func([]string, string, []string) ([]byte, error) {
		return nil, errors.New("exit status 1: no server running on /x")
	})
	rec = httptest.NewRecorder()
	SessionsHandler(rec, httptest.NewRequest("GET", "/", nil))
	if rec.Code != 200 || strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Errorf("no-server: %d %s", rec.Code, rec.Body.String())
	}
}

func TestSessionDeleteHandler(t *testing.T) {
	withSocket(t)
	calls := stubRun(t, func([]string, string, []string) ([]byte, error) { return nil, nil })
	req := httptest.NewRequest("DELETE", "/api/v1/terminal/sessions/work", nil)
	req.SetPathValue("name", "work")
	rec := httptest.NewRecorder()
	SessionDeleteHandler(rec, req)
	if rec.Code != 200 || len(*calls) != 1 || !strings.HasSuffix((*calls)[0], "kill-session -t =work") {
		t.Errorf("code=%d calls=%v", rec.Code, *calls)
	}

	req = httptest.NewRequest("DELETE", "/x", nil)
	req.SetPathValue("name", "bad name;")
	rec = httptest.NewRecorder()
	SessionDeleteHandler(rec, req)
	if rec.Code != 400 || len(*calls) != 1 {
		t.Errorf("invalid name: code=%d calls=%v", rec.Code, *calls)
	}
}
