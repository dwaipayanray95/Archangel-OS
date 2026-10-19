package system_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/dwaipayanray95/project-archangel/backend/internal/api"
	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/system"
)

func TestEndToEndSystemRoutes(t *testing.T) {
	rawToken := "test-secret-token"
	expectedHash := auth.HashToken(rawToken)

	verify := func(hash string) (string, bool) {
		return "test", hash == expectedHash
	}

	router := api.NewRouter(verify)

	// 1. Test unauthenticated request -> 401
	reqUnauth := httptest.NewRequest("GET", "/api/v1/system/metrics", nil)
	recUnauth := httptest.NewRecorder()
	router.ServeHTTP(recUnauth, reqUnauth)
	if recUnauth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized, got %d", recUnauth.Code)
	}

	// 2. Test authenticated /api/v1/system/metrics -> 200 OK
	reqMetrics := httptest.NewRequest("GET", "/api/v1/system/metrics", nil)
	reqMetrics.Header.Set("X-Archangel-Token", rawToken)
	recMetrics := httptest.NewRecorder()
	router.ServeHTTP(recMetrics, reqMetrics)

	if recMetrics.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", recMetrics.Code, recMetrics.Body.String())
	}

	var metrics system.SystemMetrics
	if err := json.Unmarshal(recMetrics.Body.Bytes(), &metrics); err != nil {
		t.Fatalf("failed decoding json metrics: %v", err)
	}
	t.Logf("Metrics Output: CPU: %.1f%% (%d cores), Memory: %d/%d bytes (%.1f%%), Disk: %.1f%%, Net Rx: %.1f B/s",
		metrics.CPU.UsagePercent, len(metrics.CPU.Cores),
		metrics.Memory.UsedBytes, metrics.Memory.TotalBytes, metrics.Memory.UsagePercent,
		metrics.Disk.UsagePercent, metrics.Network.RxBytesPerSec,
	)

	// 3. Test authenticated /api/v1/system/processes -> 200 OK
	reqProcs := httptest.NewRequest("GET", "/api/v1/system/processes", nil)
	reqProcs.Header.Set("X-Archangel-Token", rawToken)
	recProcs := httptest.NewRecorder()
	router.ServeHTTP(recProcs, reqProcs)

	if recProcs.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", recProcs.Code, recProcs.Body.String())
	}

	var procs system.ProcessListResponse
	if err := json.Unmarshal(recProcs.Body.Bytes(), &procs); err != nil {
		t.Fatalf("failed decoding json procs: %v", err)
	}
	t.Logf("Processes Output: total %d, top process: %s (PID %d, CPU %.1f%%, MEM %.1f%%)",
		procs.TotalCount, procs.Processes[0].Name, procs.Processes[0].PID,
		procs.Processes[0].CPUPercent, procs.Processes[0].MemPercent,
	)
}
