package adminmode

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestIsSudoDenied(t *testing.T) {
	for _, s := range []string{
		"sudo: a password is required",
		"sudo: no tty present and no askpass program specified",
		"archangel is not in the sudoers file.",
		"Sorry, user archangel is not allowed to execute '/bin/rm' as root",
		"user archangel may not run sudo on host",
	} {
		if !IsSudoDenied(s) {
			t.Errorf("IsSudoDenied(%q) = false", s)
		}
	}
	for _, s := range []string{"", "Failed to restart x.service: Unit not found.", "rm: cannot remove"} {
		if IsSudoDenied(s) {
			t.Errorf("IsSudoDenied(%q) = true", s)
		}
	}
}

// stub replaces runCmd and records calls.
func stub(t *testing.T, fn func(name string, args []string) (string, string, error)) *[][]string {
	t.Helper()
	oldLook := lookPath
	lookPath = func(string) (string, error) { return "", errors.New("not found") }
	t.Cleanup(func() { lookPath = oldLook })
	var calls [][]string
	old := runCmd
	runCmd = func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		calls = append(calls, append([]string{name}, args...))
		o, e, err := fn(name, args)
		return []byte(o), []byte(e), err
	}
	t.Cleanup(func() { runCmd = old })
	return &calls
}

func TestRunMapsSudoDenialToErrOff(t *testing.T) {
	calls := stub(t, func(string, []string) (string, string, error) {
		return "", "sudo: a password is required", errors.New("exit status 1")
	})
	_, err := Run(time.Second, "systemctl", "restart", "x")
	if !errors.Is(err, ErrOff) {
		t.Fatalf("err = %v, want ErrOff", err)
	}
	if got := strings.Join((*calls)[0], " "); got != "sudo -n systemctl restart x" {
		t.Errorf("command = %q", got)
	}
}

func TestRunPassesThroughCommandFailure(t *testing.T) {
	stub(t, func(string, []string) (string, string, error) {
		return "", "Unit x.service not found.", errors.New("exit status 5")
	})
	_, err := Run(time.Second, "systemctl", "start", "x")
	if err == nil || errors.Is(err, ErrOff) || !strings.Contains(err.Error(), "not found") {
		t.Errorf("err = %v", err)
	}
}

func TestGetHandler(t *testing.T) {
	stub(t, func(string, []string) (string, string, error) { return "", "", nil })
	rec := httptest.NewRecorder()
	GetHandler(rec, httptest.NewRequest("GET", "/api/v1/system/admin-mode", nil))
	body := rec.Body.String()
	if !strings.Contains(body, `"enabled":true`) || !strings.Contains(body, SudoersPath) {
		t.Errorf("body = %s", body)
	}
}

func TestSetHandlerEnableIs409(t *testing.T) {
	calls := stub(t, func(string, []string) (string, string, error) { return "", "", nil })
	rec := httptest.NewRecorder()
	SetHandler(rec, httptest.NewRequest("POST", "/", strings.NewReader(`{"enabled":true}`)))
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "SSH key") {
		t.Errorf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	if len(*calls) != 0 {
		t.Error("enable must not run anything")
	}
}

func TestSetHandlerDisableRemovesGrant(t *testing.T) {
	removed := false
	calls := stub(t, func(_ string, args []string) (string, string, error) {
		if len(args) > 1 && args[1] == "rm" {
			removed = true
			return "", "", nil
		}
		if removed {
			return "", "sudo: a password is required", errors.New("exit status 1")
		}
		return "", "", nil
	})
	rec := httptest.NewRecorder()
	SetHandler(rec, httptest.NewRequest("POST", "/", strings.NewReader(`{"enabled":false}`)))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"enabled":false`) {
		t.Errorf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	found := false
	for _, c := range *calls {
		if strings.Join(c, " ") == "sudo -n rm -f "+SudoersPath {
			found = true
		}
	}
	if !found {
		t.Errorf("rm not invoked: %v", *calls)
	}
}

func TestSetHandlerBadBody(t *testing.T) {
	rec := httptest.NewRecorder()
	SetHandler(rec, httptest.NewRequest("POST", "/", strings.NewReader(`{}`)))
	if rec.Code != http.StatusBadRequest {
		t.Errorf("code = %d", rec.Code)
	}
}

func TestRunEscapesSandboxWithSystemdRun(t *testing.T) {
	calls := stub(t, func(string, []string) (string, string, error) { return "", "", nil })
	lookPath = func(string) (string, error) { return "/usr/bin/systemd-run", nil }
	if _, err := Run(time.Second, "rm", "-f", SudoersPath); err != nil {
		t.Fatal(err)
	}
	want := "sudo -n systemd-run --quiet --wait --pipe --collect --service-type=exec -- rm -f " + SudoersPath
	if got := strings.Join((*calls)[0], " "); got != want {
		t.Errorf("command = %q, want %q", got, want)
	}
	if !Enabled() {
		t.Error("Enabled should be true")
	}
	if got := strings.Join((*calls)[1], " "); got != "sudo -n true" {
		t.Errorf("Enabled probe = %q, want plain sudo -n true", got)
	}
}
