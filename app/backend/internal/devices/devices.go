// Package devices exposes the paired-device list and revoke endpoints.
// Listing reads the token store directly (the group-readable tokens.json);
// revoking needs root (rewriting wg0.conf, `wg set`, writing tokens.json),
// so it shells out to `sudo -n <this binary> unpair <name>` - the same code
// path as the CLI, and subject to Admin mode like everything else that
// needs root.
package devices

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/dwaipayanray95/project-archangel/backend/internal/adminmode"
	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/tokenstore"
)

var (
	mu         sync.RWMutex
	storePath  string
	configPath string
)

// Configure tells the handlers where the token store and server config
// live (the latter is passed to the `unpair` subprocess).
func Configure(tokenStorePath, cfgPath string) {
	mu.Lock()
	defer mu.Unlock()
	storePath, configPath = tokenStorePath, cfgPath
}

// Device is one entry of GET /api/v1/devices. Token hashes are never exposed.
type Device struct {
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
	TunnelIP  string    `json:"tunnel_ip,omitempty"`
	// Current is true for the device making this very request.
	Current bool `json:"current,omitempty"`
}

// buildList converts store entries to API devices, flagging the caller.
func buildList(entries []tokenstore.Entry, caller string) []Device {
	list := make([]Device, 0, len(entries))
	for _, e := range entries {
		list = append(list, Device{
			Name:      e.Name,
			CreatedAt: e.CreatedAt,
			TunnelIP:  e.TunnelIP,
			Current:   caller != "" && e.Name == caller,
		})
	}
	return list
}

// ListHandler handles GET /api/v1/devices
func ListHandler(w http.ResponseWriter, r *http.Request) {
	mu.RLock()
	path := storePath
	mu.RUnlock()

	store, err := tokenstore.Load(path)
	if err != nil {
		slog.Error("devices: loading token store", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "failed to read paired devices"})
		return
	}
	writeJSON(w, http.StatusOK, buildList(store.Entries(), auth.DeviceName(r.Context())))
}

// unpair runs the privileged revoke. A var so tests don't need sudo.
var unpair = func(name string) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	mu.RLock()
	cfg := configPath
	mu.RUnlock()
	args := []string{exe, "unpair"}
	if cfg != "" {
		args = append(args, "--config", cfg)
	}
	args = append(args, name)
	_, err = adminmode.Run(30*time.Second, args...)
	return err
}

// DeleteHandler handles DELETE /api/v1/devices/{name}[?self=true]
func DeleteHandler(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if err := tokenstore.ValidateDeviceName(name); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": err.Error()})
		return
	}

	mu.RLock()
	path := storePath
	mu.RUnlock()
	store, err := tokenstore.Load(path)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "failed to read paired devices"})
		return
	}
	if _, ok := store.Find(name); !ok {
		writeJSON(w, http.StatusNotFound, map[string]any{"success": false, "message": "no such device"})
		return
	}

	// Revoking yourself cuts the tunnel you're talking over, so it needs an
	// explicit opt-in.
	if auth.DeviceName(r.Context()) == name && r.URL.Query().Get("self") != "true" {
		writeJSON(w, http.StatusConflict, map[string]any{
			"success": false,
			"message": "This is the device you are using; revoking it will disconnect you. Retry with ?self=true to confirm.",
		})
		return
	}

	slog.Warn("revoking device via API", "device", name)
	if err := unpair(name); err != nil {
		status := http.StatusInternalServerError
		if err == adminmode.ErrOff {
			status = http.StatusForbidden
		}
		writeJSON(w, status, map[string]any{"success": false, "message": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "device " + name + " revoked"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
