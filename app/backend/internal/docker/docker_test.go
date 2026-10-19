package docker_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/dwaipayanray95/project-archangel/backend/internal/docker"
)

func init() {
	// Force the unavailable path regardless of whether the machine
	// running these tests happens to have a live Docker daemon at the
	// default socket path (true on GitHub Actions' ubuntu-latest runners).
	docker.SetDefaultClient(docker.NewClient("/nonexistent/docker.sock"))
}

func TestContainersHandlerFallback(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/docker/containers", nil)
	rec := httptest.NewRecorder()

	docker.ContainersHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var overview docker.ContainersOverview
	if err := json.Unmarshal(rec.Body.Bytes(), &overview); err != nil {
		t.Fatalf("failed decoding json: %v", err)
	}

	if overview.DockerAvailable {
		t.Errorf("expected DockerAvailable=false in fallback, got true")
	}

	if overview.RunningCount != 0 || overview.StoppedCount != 0 {
		t.Errorf("expected 0 running/stopped in fallback, got %d/%d", overview.RunningCount, overview.StoppedCount)
	}
}

func assertUnavailable(t *testing.T, rec *httptest.ResponseRecorder) {
	t.Helper()
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rec.Code)
	}
	var res docker.ActionResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed decoding json: %v", err)
	}
	if res.Success || res.Message != "Docker is not running on this server" {
		t.Errorf("unexpected response: %+v", res)
	}
}

func TestContainerActionHandlerUnavailable(t *testing.T) {
	for _, action := range []string{"restart", "remove"} {
		req := httptest.NewRequest("POST", "/api/v1/docker/containers/caddy/"+action, nil)
		req.SetPathValue("id", "caddy")
		req.SetPathValue("action", action)
		rec := httptest.NewRecorder()
		docker.ContainerActionHandler(rec, req)
		assertUnavailable(t, rec)
	}
}

func TestContainerCreateHandlerUnavailable(t *testing.T) {
	body := `{"image":"nginx:alpine","name":"test-web","ports":["8080:80"],"restart":"unless-stopped"}`
	req := httptest.NewRequest("POST", "/api/v1/docker/containers/run", strings.NewReader(body))
	rec := httptest.NewRecorder()
	docker.ContainerCreateHandler(rec, req)
	assertUnavailable(t, rec)
}

func TestGetVersionOfflineIsNotFabricated(t *testing.T) {
	if v := docker.NewClient("/nonexistent/docker.sock").GetVersion(); v == "27.1.1" {
		t.Errorf("GetVersion returned a fabricated version %q", v)
	}
}
