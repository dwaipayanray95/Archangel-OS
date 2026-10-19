package docker

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

const defaultSocketPath = "/var/run/docker.sock"

// validContainerID matches Docker's own container ID/name charset. Any
// endpoint that splices a caller-supplied id into the Docker Engine API
// request path must reject anything not matching this first - the id is
// never otherwise escaped, so an unvalidated value (e.g. containing "/"
// or "..") could redirect the request to a different Engine API endpoint
// entirely over the Unix socket, which is root-equivalent access.
var validContainerID = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`)

// validImageName validates Docker image references (e.g. nginx, alpine:3.18, ghcr.io/org/repo:v1).
var validImageName = regexp.MustCompile(`^[a-zA-Z0-9_./:-]+$`)

// Client interacts directly with Docker Engine via the local Unix socket.
type Client struct {
	http   *http.Client
	socket string
}

// NewClient creates a Docker socket client.
func NewClient(socketPath ...string) *Client {
	sock := defaultSocketPath
	if len(socketPath) > 0 && socketPath[0] != "" {
		sock = socketPath[0]
	}

	tr := &http.Transport{
		DialContext: func(ctx context.Context, proto, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", sock)
		},
		DisableKeepAlives: true,
	}

	return &Client{
		http:   &http.Client{Transport: tr},
		socket: sock,
	}
}

// IsAvailable checks if the Docker Unix domain socket exists and responds.
func (c *Client) IsAvailable() bool {
	if _, err := os.Stat(c.socket); err != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://localhost/version", nil)
	if err != nil {
		return false
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// GetVersion returns Docker engine version string.
func (c *Client) GetVersion() string {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://localhost/version", nil)
	if err != nil {
		return "offline"
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return "offline"
	}
	defer resp.Body.Close()

	var data struct {
		Version string `json:"Version"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err == nil && data.Version != "" {
		return data.Version
	}
	// Never invent a version number: if the daemon answered but gave us
	// nothing parseable, say so honestly.
	return "unknown"
}

// ListContainers returns parsed container summaries with stack classification.
func (c *Client) ListContainers() ([]ContainerItem, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://localhost/containers/json?all=true", nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("docker API error %d: %s", resp.StatusCode, string(body))
	}

	var rawList []struct {
		ID      string            `json:"Id"`
		Names   []string          `json:"Names"`
		Image   string            `json:"Image"`
		State   string            `json:"State"`
		Status  string            `json:"Status"`
		Created int64             `json:"Created"`
		Labels  map[string]string `json:"Labels"`
		Ports   []struct {
			PrivatePort int    `json:"PrivatePort"`
			PublicPort  int    `json:"PublicPort"`
			Type        string `json:"Type"`
		} `json:"Ports"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&rawList); err != nil {
		return nil, err
	}

	result := make([]ContainerItem, 0, len(rawList))
	for _, r := range rawList {
		name := ""
		if len(r.Names) > 0 {
			name = strings.TrimPrefix(r.Names[0], "/")
		}

		stack := "standalone"
		if proj, ok := r.Labels["com.docker.compose.project"]; ok && proj != "" {
			stack = proj
		}

		cid := r.ID
		if len(cid) > 12 {
			cid = cid[:12]
		}

		portsList := make([]string, 0, len(r.Ports))
		for _, p := range r.Ports {
			if p.PublicPort > 0 {
				portsList = append(portsList, fmt.Sprintf("%d", p.PublicPort))
			} else if p.PrivatePort > 0 {
				portsList = append(portsList, fmt.Sprintf("%d", p.PrivatePort))
			}
		}
		ports := strings.Join(portsList, ",")
		if ports == "" {
			ports = "—"
		}

		running := strings.ToLower(r.State) == "running"

		// Format simple uptime
		uptime := r.Status
		if strings.HasPrefix(uptime, "Up ") {
			parts := strings.Split(uptime, " ")
			if len(parts) >= 3 && parts[2] != "" {
				uptime = "up " + parts[1] + parts[2][:1]
			}
		}

		result = append(result, ContainerItem{
			ID:       r.ID,
			Names:    r.Names,
			Name:     name,
			Image:    r.Image,
			Stack:    stack,
			State:    r.State,
			Status:   r.Status,
			Uptime:   uptime,
			CPU:      0.0,
			MemMb:    0,
			MemLabel: "—",
			Ports:    ports,
			CID:      cid,
			Running:  running,
			Labels:   r.Labels,
		})
	}

	// CPU/memory come from the background stats cache (see stats.go) so
	// listing never blocks on Docker's slow per-container /stats calls.
	mergeStats(result, globalStats, time.Now())

	return result, nil
}

// ContainerAction triggers start, stop, restart, or remove.
func (c *Client) ContainerAction(id, action string) error {
	if !validContainerID.MatchString(id) {
		return fmt.Errorf("invalid container id")
	}

	var endpoint string
	method := http.MethodPost
	switch action {
	case "start":
		endpoint = fmt.Sprintf("http://localhost/containers/%s/start", id)
	case "stop":
		endpoint = fmt.Sprintf("http://localhost/containers/%s/stop?t=10", id)
	case "restart":
		endpoint = fmt.Sprintf("http://localhost/containers/%s/restart?t=10", id)
	case "remove", "rm":
		endpoint = fmt.Sprintf("http://localhost/containers/%s?force=true", id)
		method = http.MethodDelete
	default:
		return fmt.Errorf("unsupported action: %s", action)
	}

	req, err := http.NewRequest(method, endpoint, nil)
	if err != nil {
		return err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusNotModified {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("docker API error %d: %s", resp.StatusCode, string(body))
	}
	return nil
}

// PullImage pulls a Docker image from registry over the Engine API.
func (c *Client) PullImage(ctx context.Context, image string) error {
	if !validImageName.MatchString(image) {
		return fmt.Errorf("invalid image name")
	}

	endpoint := fmt.Sprintf("http://localhost/images/create?fromImage=%s", url.QueryEscape(image))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, nil)
	if err != nil {
		return err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("failed to pull image %s (status %d): %s", image, resp.StatusCode, string(body))
	}

	// Drain streaming body to wait for pull to complete
	_, _ = io.Copy(io.Discard, resp.Body)
	return nil
}

// CreateAndStartContainer creates and starts a Docker container.
func (c *Client) CreateAndStartContainer(ctx context.Context, req CreateContainerRequest) (string, error) {
	cleanImage := strings.TrimSpace(req.Image)
	if cleanImage == "" || !validImageName.MatchString(cleanImage) {
		return "", fmt.Errorf("invalid or missing image name")
	}

	cleanName := strings.TrimSpace(req.Name)
	if cleanName != "" && !validContainerID.MatchString(cleanName) {
		return "", fmt.Errorf("invalid container name: %s", cleanName)
	}

	// Prepare ports. See ParsePortSpec for the accepted formats and the
	// private-by-default publishing rule.
	exposedPorts := make(map[string]struct{})
	portBindings := make(map[string][]map[string]string)

	for _, p := range req.Ports {
		spec, err := ParsePortSpec(p, privateBindIP())
		if err != nil {
			return "", err
		}
		if spec == nil {
			continue
		}
		exposedPorts[spec.ContainerPort] = struct{}{}
		if spec.HostPort != "" {
			portBindings[spec.ContainerPort] = append(portBindings[spec.ContainerPort], map[string]string{
				"HostIp":   spec.HostIP,
				"HostPort": spec.HostPort,
			})
		}
	}

	var cleanVolumes []string
	for _, v := range req.Volumes {
		v = strings.TrimSpace(v)
		if v != "" {
			cleanVolumes = append(cleanVolumes, v)
		}
	}

	restartPolicy := req.Restart
	if restartPolicy == "" {
		restartPolicy = "unless-stopped"
	}

	payload := map[string]any{
		"Image":        cleanImage,
		"Env":          req.Env,
		"ExposedPorts": exposedPorts,
		"HostConfig": map[string]any{
			"PortBindings": portBindings,
			"RestartPolicy": map[string]string{
				"Name": restartPolicy,
			},
			"Binds": cleanVolumes,
		},
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal container config: %w", err)
	}

	createEndpoint := "http://localhost/containers/create"
	if cleanName != "" {
		createEndpoint += "?name=" + url.QueryEscape(cleanName)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, createEndpoint, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", err
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(httpReq)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	// If image not found, pull it and retry creation
	if resp.StatusCode == http.StatusNotFound {
		pullCtx, pullCancel := context.WithTimeout(ctx, 3*time.Minute)
		defer pullCancel()
		if err := c.PullImage(pullCtx, cleanImage); err != nil {
			return "", fmt.Errorf("image not found locally and pull failed: %w", err)
		}

		retryReq, err := http.NewRequestWithContext(ctx, http.MethodPost, createEndpoint, bytes.NewReader(bodyBytes))
		if err != nil {
			return "", err
		}
		retryReq.Header.Set("Content-Type", "application/json")

		resp, err = c.http.Do(retryReq)
		if err != nil {
			return "", err
		}
		defer resp.Body.Close()
	}

	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("docker create container error %d: %s", resp.StatusCode, string(respBody))
	}

	var createResp struct {
		ID       string   `json:"Id"`
		Warnings []string `json:"Warnings"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&createResp); err != nil {
		return "", fmt.Errorf("failed to decode create response: %w", err)
	}

	// Start container
	if err := c.ContainerAction(createResp.ID, "start"); err != nil {
		return createResp.ID, fmt.Errorf("container created (%s) but failed to start: %w", createResp.ID, err)
	}

	return createResp.ID, nil
}

// ContainerStats fetches instantaneous CPU and Memory statistics for a container.
func (c *Client) ContainerStats(ctx context.Context, id string) (cpu float64, memMb int64, memLabel string, err error) {
	if !validContainerID.MatchString(id) {
		return 0, 0, "—", fmt.Errorf("invalid container id")
	}

	endpoint := fmt.Sprintf("http://localhost/containers/%s/stats?stream=false", id)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return 0, 0, "—", err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return 0, 0, "—", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return 0, 0, "—", fmt.Errorf("stats error %d", resp.StatusCode)
	}

	var data struct {
		CPUStats struct {
			CPUUsage struct {
				TotalUsage uint64 `json:"total_usage"`
			} `json:"cpu_usage"`
			SystemCPUUsage uint64 `json:"system_cpu_usage"`
			OnlineCPUs     uint32 `json:"online_cpus"`
		} `json:"cpu_stats"`
		PreCPUStats struct {
			CPUUsage struct {
				TotalUsage uint64 `json:"total_usage"`
			} `json:"cpu_usage"`
			SystemCPUUsage uint64 `json:"system_cpu_usage"`
		} `json:"precpu_stats"`
		MemoryStats struct {
			Usage uint64 `json:"usage"`
			Limit uint64 `json:"limit"`
			Stats map[string]uint64 `json:"stats"`
		} `json:"memory_stats"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return 0, 0, "—", err
	}

	// Calculate CPU %
	cpuDelta := float64(data.CPUStats.CPUUsage.TotalUsage) - float64(data.PreCPUStats.CPUUsage.TotalUsage)
	systemDelta := float64(data.CPUStats.SystemCPUUsage) - float64(data.PreCPUStats.SystemCPUUsage)
	onlineCPUs := float64(data.CPUStats.OnlineCPUs)
	if onlineCPUs == 0 {
		onlineCPUs = 1.0
	}

	if systemDelta > 0 && cpuDelta > 0 {
		cpu = (cpuDelta / systemDelta) * onlineCPUs * 100.0
		// Round to 1 decimal place
		cpu = float64(int(cpu*10)) / 10.0
	}

	// Memory usage (subtract cache / inactive_file if available like Docker CLI does)
	usedBytes := data.MemoryStats.Usage
	if cache, ok := data.MemoryStats.Stats["inactive_file"]; ok && cache < usedBytes {
		usedBytes -= cache
	} else if cache, ok := data.MemoryStats.Stats["cache"]; ok && cache < usedBytes {
		usedBytes -= cache
	}

	memMb = int64(usedBytes / (1024 * 1024))
	if memMb >= 1024 {
		memLabel = fmt.Sprintf("%.1f GB", float64(memMb)/1024.0)
	} else if memMb > 0 {
		memLabel = fmt.Sprintf("%d MB", memMb)
	} else {
		memLabel = "—"
	}

	return cpu, memMb, memLabel, nil
}

// IsTTY reports whether a container was created with a TTY attached
// (docker run -t). Docker's /logs endpoint only multiplexes stdout/stderr
// into the 8-byte-header framed protocol for non-TTY containers - a TTY
// container's logs are raw bytes, so callers must check this before
// deciding how to parse the stream.
func (c *Client) IsTTY(ctx context.Context, id string) (bool, error) {
	if !validContainerID.MatchString(id) {
		return false, fmt.Errorf("invalid container id")
	}

	endpoint := fmt.Sprintf("http://localhost/containers/%s/json", id)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return false, err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("docker inspect error %d", resp.StatusCode)
	}

	var data struct {
		Config struct {
			Tty bool `json:"Tty"`
		} `json:"Config"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return false, err
	}
	return data.Config.Tty, nil
}

// StreamLogsReader opens a raw streaming reader to Docker's container logs.
func (c *Client) StreamLogsReader(ctx context.Context, id string, tail int) (io.ReadCloser, error) {
	if !validContainerID.MatchString(id) {
		return nil, fmt.Errorf("invalid container id")
	}

	endpoint := fmt.Sprintf("http://localhost/containers/%s/logs?follow=1&stdout=1&stderr=1&tail=%d&timestamps=1", id, tail)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("docker logs error %d", resp.StatusCode)
	}

	return resp.Body, nil
}

// FallbackOverview provides empty/offline state if Docker daemon is not running or socket is missing.
func FallbackOverview() *ContainersOverview {
	return &ContainersOverview{
		DockerAvailable: false,
		EngineVersion:   "offline / unavailable",
		RunningCount:    0,
		StoppedCount:    0,
		TotalImagesSize: "0 B",
		Containers:      []ContainerItem{},
		Stacks:          []string{},
		StackMeta:       map[string]string{},
	}
}
