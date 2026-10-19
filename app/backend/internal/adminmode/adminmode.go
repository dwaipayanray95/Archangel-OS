// Package adminmode wraps the "Admin mode" privilege model: the server
// grants the unprivileged `archangel` user passwordless sudo through
// /etc/sudoers.d/archangel. Everything in the backend that needs root goes
// through Run (always `sudo -n`, never prompting), and when the grant is
// absent the caller gets one consistent, human-readable error instead of a
// hung prompt or a cryptic sudo message.
//
// The API deliberately lets a client switch Admin mode OFF but never ON: a
// leaked app token can drop privileges but can't regain them. Re-enabling
// needs the owner's SSH key (the app does it over SSH, outside this
// process).
package adminmode

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

// SudoersPath is the drop-in file that constitutes the Admin mode grant.
const SudoersPath = "/etc/sudoers.d/archangel"

// OffMessage is what users see when an action needs root and the grant is gone.
const OffMessage = "Admin mode is off - this action needs it"

// ErrOff is returned (wrapped by nothing, compare with errors.Is) when sudo
// refused to run a command non-interactively.
var ErrOff = errors.New(OffMessage)

// runCmd executes a command and returns stdout, stderr and the run error.
// A package-level var so tests can stub out the real sudo.
var runCmd = func(ctx context.Context, name string, args ...string) (stdout, stderr []byte, err error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var o, e bytes.Buffer
	cmd.Stdout, cmd.Stderr = &o, &e
	err = cmd.Run()
	return o.Bytes(), e.Bytes(), err
}

// IsSudoDenied reports whether sudo's stderr means "you aren't allowed /
// would need a password" (as opposed to the sudo'd command itself failing).
func IsSudoDenied(stderr string) bool {
	s := strings.ToLower(stderr)
	for _, marker := range []string{
		"a password is required",
		"a terminal is required",
		"no tty present",
		"may not run sudo",
		"is not in the sudoers",
		"not allowed to execute",
		"not allowed to run sudo",
	} {
		if strings.Contains(s, marker) {
			return true
		}
	}
	return false
}

// lookPath is swappable in tests.
var lookPath = exec.LookPath

// escapeArgs wraps a privileged command in `systemd-run --pipe --wait` so
// PID 1 runs it as a transient unit outside archangel.service's sandbox.
// sudo alone is not enough: sudo's children inherit the unit's mount
// namespace, where ProtectSystem=full and ReadOnlyPaths keep /etc
// read-only even for root - so `rm /etc/sudoers.d/archangel`, `unpair`
// (which rewrites /etc/wireguard/wg0.conf and /etc/archangel/tokens.json)
// and similar would fail with "Read-only file system". Falls back to the
// bare command where systemd-run doesn't exist (non-systemd dev boxes).
func escapeArgs(args []string) []string {
	if _, err := lookPath("systemd-run"); err != nil {
		return args
	}
	return append([]string{"systemd-run", "--quiet", "--wait", "--pipe", "--collect", "--service-type=exec", "--"}, args...)
}

// Run executes `sudo -n <args...>` with a timeout, outside the service
// sandbox (see escapeArgs). It returns ErrOff when sudo refused (Admin
// mode off); other failures include the command's stderr. stdout is
// returned on success.
func Run(timeout time.Duration, args ...string) ([]byte, error) {
	return run(timeout, escapeArgs(args))
}

func run(timeout time.Duration, args []string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	stdout, stderr, err := runCmd(ctx, "sudo", append([]string{"-n"}, args...)...)
	if err == nil {
		return stdout, nil
	}
	if IsSudoDenied(string(stderr)) {
		return nil, ErrOff
	}
	if ctx.Err() != nil {
		return nil, fmt.Errorf("timed out after %s", timeout)
	}
	if msg := strings.TrimSpace(string(stderr)); msg != "" {
		return nil, fmt.Errorf("%v (%s)", err, msg)
	}
	return nil, err
}

// Enabled reports whether passwordless sudo currently works (`sudo -n true`
// succeeds within 2 seconds).
func Enabled() bool {
	// Probes sudo itself, so no need to escape the sandbox.
	_, err := run(2*time.Second, []string{"true"})
	return err == nil
}

type statusResponse struct {
	Enabled     bool   `json:"enabled"`
	SudoersPath string `json:"sudoers_path"`
}

// GetHandler handles GET /api/v1/system/admin-mode
func GetHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, statusResponse{Enabled: Enabled(), SudoersPath: SudoersPath})
}

type setRequest struct {
	Enabled *bool `json:"enabled"`
}

// SetHandler handles POST /api/v1/system/admin-mode. Only {"enabled":false}
// is honoured; true is a 409 by design (see package comment).
func SetHandler(w http.ResponseWriter, r *http.Request) {
	var req setRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil || req.Enabled == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"message": `expected {"enabled": false}`})
		return
	}

	if *req.Enabled {
		writeJSON(w, http.StatusConflict, map[string]string{
			"message": "Re-enabling Admin mode requires the owner's SSH key - the app does it over SSH. " +
				"The API can only turn it off, so a leaked app token can never gain privileges.",
		})
		return
	}

	// Already off: nothing to do (and `sudo rm` would just fail).
	if !Enabled() {
		writeJSON(w, http.StatusOK, statusResponse{Enabled: false, SudoersPath: SudoersPath})
		return
	}

	slog.Warn("admin mode being switched off via API")
	if _, err := Run(5*time.Second, "rm", "-f", SudoersPath); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"message": "failed to remove sudoers grant: " + err.Error()})
		return
	}
	// Report the real state: another sudoers rule could still grant access.
	writeJSON(w, http.StatusOK, statusResponse{Enabled: Enabled(), SudoersPath: SudoersPath})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
