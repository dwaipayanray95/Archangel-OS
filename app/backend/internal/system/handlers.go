package system

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"runtime"
	"strconv"
	"time"

	"github.com/gorilla/websocket"

	"github.com/dwaipayanray95/project-archangel/backend/internal/adminmode"
)

var upgrader = websocket.Upgrader{}

// MetricsHandler handles GET /api/v1/system/metrics
func MetricsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	metrics := GetCollector().Latest()
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(metrics); err != nil {
		slog.Error("failed encoding metrics response", "err", err)
	}
}

// ProcessesHandler handles GET /api/v1/system/processes
func ProcessesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	procs, err := ListProcesses()
	if err != nil {
		slog.Error("failed listing processes", "err", err)
		http.Error(w, "failed listing processes", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(procs)
}

type killRequest struct {
	Force bool `json:"force"`
}

// ProcessKillHandler handles POST /api/v1/system/processes/{pid}/kill
func ProcessKillHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	pidStr := r.PathValue("pid")
	pid, err := strconv.Atoi(pidStr)
	if err != nil {
		http.Error(w, "invalid pid", http.StatusBadRequest)
		return
	}

	var req killRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}

	if err := KillProcess(pid, req.Force); err != nil {
		slog.Warn("kill process failed", "pid", pid, "err", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"status": "ok", "pid": pid})
}

type reniceRequest struct {
	Priority int `json:"priority"`
}

// ProcessReniceHandler handles POST /api/v1/system/processes/{pid}/renice
func ProcessReniceHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	pidStr := r.PathValue("pid")
	pid, err := strconv.Atoi(pidStr)
	if err != nil {
		http.Error(w, "invalid pid", http.StatusBadRequest)
		return
	}

	var req reniceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if err := ReniceProcess(pid, req.Priority); err != nil {
		slog.Warn("renice process failed", "pid", pid, "err", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"status": "ok", "pid": pid, "priority": req.Priority})
}

// RebootHandler handles POST /api/v1/system/reboot
func RebootHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Check privileges BEFORE answering OK: previously the 200 went out
	// first and a failed sudo in the background goroutine was silently
	// ignored, so the app announced a reboot that never happened.
	if runtime.GOOS == "linux" && !adminmode.Enabled() {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":  "error",
			"message": adminmode.OffMessage,
		})
		return
	}

	slog.Warn("system reboot requested via API")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status":  "ok",
		"message": "reboot initiated",
	})

	go func() {
		time.Sleep(1 * time.Second)
		if runtime.GOOS == "linux" {
			if _, err := adminmode.Run(10*time.Second, "systemctl", "reboot"); err != nil {
				slog.Error("systemctl reboot failed, trying reboot", "err", err)
				_, _ = adminmode.Run(10*time.Second, "reboot")
			}
		}
	}()
}

// StatsWsHandler handles GET /ws/stats for live streaming metrics
type clientWsControl struct {
	Action     string `json:"action"`      // "set_rate"
	IntervalMs int    `json:"interval_ms"` // e.g. 500, 1000, 5000
}

// StatsWsHandler handles GET /ws/stats for live streaming metrics
func StatsWsHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("failed upgrading ws/stats", "err", err)
		return
	}
	defer conn.Close()

	// Push metrics immediately upon connect
	collector := GetCollector()
	if err := conn.WriteJSON(collector.Latest()); err != nil {
		return
	}

	interval := 2 * time.Second
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	// Rate control channel
	rateCh := make(chan time.Duration, 4)

	// Read loop to detect client disconnect and control messages (e.g. dynamic rate changes)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			_, msg, err := conn.ReadMessage()
			if err != nil {
				return
			}
			var ctrl clientWsControl
			if err := json.Unmarshal(msg, &ctrl); err == nil && ctrl.Action == "set_rate" {
				if ctrl.IntervalMs >= 250 && ctrl.IntervalMs <= 30000 {
					select {
					case rateCh <- time.Duration(ctrl.IntervalMs) * time.Millisecond:
					default:
					}
				}
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case newDur := <-rateCh:
			ticker.Reset(newDur)
		case <-ticker.C:
			metrics := collector.Latest()
			conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err := conn.WriteJSON(metrics); err != nil {
				slog.Debug("stats ws client disconnected", "err", err)
				return
			}
		}
	}
}
