package docker

import (
	"bufio"
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

var defaultClient = NewClient()

// notRunningMessage is returned whenever an action needs Docker and the
// daemon isn't reachable. There is deliberately no demo/simulated mode:
// pretending an action succeeded would be a lie.
const notRunningMessage = "Docker is not running on this server"

func writeDockerUnavailable(w http.ResponseWriter) {
	w.WriteHeader(http.StatusServiceUnavailable)
	_ = json.NewEncoder(w).Encode(ActionResponse{Success: false, Message: notRunningMessage})
}

// SetDefaultClient overrides the package-level Docker client the HTTP
// handlers use. Exported for tests: CI runners commonly ship a real,
// live Docker daemon at the default socket path, so relying on
// IsAvailable() naturally returning false to exercise the unavailable
// path is environment-dependent - tests should point this at a client
// with a guaranteed-nonexistent socket path instead.
func SetDefaultClient(c *Client) {
	defaultClient = c
}

// ContainersHandler handles GET /api/v1/docker/containers
func ContainersHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	// Lazily start the background CPU/memory poller (once per process).
	startStatsPoller()

	if !defaultClient.IsAvailable() {
		_ = json.NewEncoder(w).Encode(FallbackOverview())
		return
	}

	containers, err := defaultClient.ListContainers()
	if err != nil {
		_ = json.NewEncoder(w).Encode(FallbackOverview())
		return
	}

	running := 0
	stopped := 0
	stacksMap := make(map[string]int)
	for _, c := range containers {
		if c.Running {
			running++
		} else {
			stopped++
		}
		stacksMap[c.Stack]++
	}

	stacks := make([]string, 0, len(stacksMap))
	stackMeta := make(map[string]string)
	for s, count := range stacksMap {
		stacks = append(stacks, s)
		stackMeta[s] = fmt.Sprintf("compose stack · %d services", count)
	}

	overview := ContainersOverview{
		DockerAvailable: true,
		EngineVersion:   defaultClient.GetVersion(),
		RunningCount:    running,
		StoppedCount:    stopped,
		TotalImagesSize: "—",
		Containers:      containers,
		Stacks:          stacks,
		StackMeta:       stackMeta,
	}

	_ = json.NewEncoder(w).Encode(overview)
}

// ContainerActionHandler handles POST /api/v1/docker/containers/{id}/{action}
func ContainerActionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := r.PathValue("id")
	action := r.PathValue("action")
	if id == "" || action == "" {
		http.Error(w, "missing container id or action", http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if !defaultClient.IsAvailable() {
		writeDockerUnavailable(w)
		return
	}

	err := defaultClient.ContainerAction(id, action)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: fmt.Sprintf("failed to %s container: %v", action, err),
		})
		return
	}

	actionPast := action + "ed"
	if action == "stop" {
		actionPast = "stopped"
	} else if action == "remove" || action == "rm" {
		actionPast = "removed"
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: fmt.Sprintf("container %s %s successfully", id, actionPast),
	})
}

// ContainerCreateHandler handles POST /api/v1/docker/containers/run
func ContainerCreateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CreateContainerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("invalid request payload: %v", err), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if !defaultClient.IsAvailable() {
		writeDockerUnavailable(w)
		return
	}

	id, err := defaultClient.CreateAndStartContainer(r.Context(), req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: fmt.Sprintf("container %s created and started successfully", id),
	})
}

// CheckOrigin left at its default (same-origin check) - matches the
// hardened pattern in internal/system's stats upgrader; this endpoint is
// already gated by auth.Middleware regardless.
var upgrader = websocket.Upgrader{}

// logWriteTimeout bounds each log-line write to the client.
const logWriteTimeout = 10 * time.Second

// ContainerLogsWsHandler handles GET /ws/docker/containers/{id}/logs
func ContainerLogsWsHandler(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.Error(w, "missing container id", http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	// Nothing reads from the socket otherwise, so a client disconnect would
	// go unnoticed until the next write failed (possibly never, on a quiet
	// container). Draining client messages makes ReadMessage return an error
	// on disconnect, which cancels ctx and tears down the Docker stream.
	go func() {
		defer cancel()
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()

	// writeJSON bounds every write so a stalled client can't wedge this
	// goroutine forever. Only the streaming loop below writes, so no mutex.
	writeJSON := func(v any) error {
		_ = conn.SetWriteDeadline(time.Now().Add(logWriteTimeout))
		return conn.WriteJSON(v)
	}

	if !defaultClient.IsAvailable() {
		_ = writeJSON(LogEntry{
			TS:     time.Now().Format("15:04:05"),
			Level:  "ERROR",
			Source: "docker",
			Text:   notRunningMessage,
		})
		return
	}

	// Docker only multiplexes /logs output into the 8-byte-header framed
	// protocol for containers created without a TTY - a TTY container's
	// logs are raw bytes, and parsing them as framed would misinterpret
	// arbitrary log content as stream-type/payload-size headers.
	tty, err := defaultClient.IsTTY(ctx, id)
	if err != nil {
		tty = false
	}

	stream, err := defaultClient.StreamLogsReader(ctx, id, 100)
	if err != nil {
		_ = writeJSON(LogEntry{
			TS:     time.Now().Format("15:04:05"),
			Level:  "ERROR",
			Source: "docker",
			Text:   fmt.Sprintf("failed to attach to logs: %v", err),
		})
		return
	}
	defer stream.Close()

	reader := bufio.NewReader(stream)

	emit := func(streamType byte, raw string) bool {
		clean := strings.TrimRight(raw, "\r\n")
		if clean == "" {
			return true
		}

		level := "INFO"
		if streamType == 2 {
			level = "ERROR"
		} else if strings.Contains(strings.ToUpper(clean), "WARN") {
			level = "WARN"
		} else if strings.Contains(strings.ToUpper(clean), "ERR") {
			level = "ERROR"
		}

		ts := time.Now().Format("15:04:05")
		// Docker with timestamps=1 outputs: 2026-09-11T09:12:34.123456789Z <message>
		if len(clean) > 31 && clean[4] == '-' && clean[7] == '-' && (clean[10] == 'T' || clean[10] == ' ') {
			if t, err := time.Parse(time.RFC3339Nano, strings.Replace(clean[:30], " ", "T", 1)); err == nil {
				ts = t.Format("15:04:05")
				clean = strings.TrimSpace(clean[30:])
			}
		}

		entry := LogEntry{
			TS:     ts,
			Level:  level,
			Source: id,
			Text:   clean,
		}
		return writeJSON(entry) == nil
	}

	if tty {
		// Raw, unframed byte stream - read line by line.
		for {
			line, err := reader.ReadString('\n')
			if line != "" && !emit(1, line) {
				break
			}
			if err != nil {
				break
			}
		}
		return
	}

	// Docker Multiplex Log Protocol:
	// Each frame starts with an 8-byte header:
	//   header[0] = stream type (1 = stdout, 2 = stderr, 0 = stdin)
	//   header[1..3] = 0 (reserved)
	//   header[4..7] = uint32 big-endian payload size
	headerBuf := make([]byte, 8)

	for {
		// Read 8-byte header
		_, err := io.ReadFull(reader, headerBuf)
		if err != nil {
			break
		}

		streamType := headerBuf[0]
		payloadSize := binary.BigEndian.Uint32(headerBuf[4:8])

		// Bound frame size to 1MB to prevent memory exhaustion
		if payloadSize > 1024*1024 {
			break
		}

		payload := make([]byte, payloadSize)
		_, err = io.ReadFull(reader, payload)
		if err != nil {
			break
		}

		if !emit(streamType, string(payload)) {
			break
		}
	}
}
