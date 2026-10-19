package docker

// ContainerItem represents a single container's runtime state.
type ContainerItem struct {
	ID       string            `json:"id"`
	Names    []string          `json:"names"`
	Name     string            `json:"name"`
	Image    string            `json:"image"`
	Stack    string            `json:"stack"`  // From com.docker.compose.project or "standalone"
	State    string            `json:"state"`  // "running", "exited", "paused", etc.
	Status   string            `json:"status"` // e.g. "Up 42 days", "Exited (0) 6 hours ago"
	Uptime   string            `json:"uptime"`
	CPU      float64           `json:"cpu"` // Percentage
	MemMb    int64             `json:"mem_mb"`
	MemLabel string            `json:"mem_label"`
	Ports    string            `json:"ports"`
	CID      string            `json:"cid"` // Truncated 12-char ID
	Running  bool              `json:"running"`
	Labels   map[string]string `json:"labels,omitempty"`
}

// ContainersOverview wraps the engine status and containers payload.
type ContainersOverview struct {
	DockerAvailable bool              `json:"docker_available"`
	EngineVersion   string            `json:"engine_version"`
	RunningCount    int               `json:"running_count"`
	StoppedCount    int               `json:"stopped_count"`
	TotalImagesSize string            `json:"total_images_size"`
	Containers      []ContainerItem   `json:"containers"`
	Stacks          []string          `json:"stacks"`
	StackMeta       map[string]string `json:"stack_meta"`
}

// LogEntry is a formatted log line streamed to the frontend.
type LogEntry struct {
	TS     string `json:"ts"`
	Level  string `json:"level"`
	Source string `json:"source"`
	Text   string `json:"text"`
}

// ActionResponse represents standard start/stop/restart feedback.
type ActionResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// CreateContainerRequest contains parameters for spinning up a new container.
type CreateContainerRequest struct {
	Image   string   `json:"image"`
	Name    string   `json:"name,omitempty"`
	Ports   []string `json:"ports,omitempty"`   // Format: "8080:80" or "80"
	Env     []string `json:"env,omitempty"`     // Format: "KEY=VALUE"
	Restart string   `json:"restart,omitempty"` // "no", "always", "unless-stopped", "on-failure"
	Volumes []string `json:"volumes,omitempty"` // Format: "/host/path:/container/path"
}
