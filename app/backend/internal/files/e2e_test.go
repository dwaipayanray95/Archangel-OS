package files_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/dwaipayanray95/project-archangel/backend/internal/api"
	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/files"
)

func TestFilesRoutesAuthAndExecution(t *testing.T) {
	rawToken := "auth-token-xyz"
	expectedHash := auth.HashToken(rawToken)
	router := api.NewRouter(func(h string) (string, bool) { return "test", h == expectedHash })

	tmpDir := t.TempDir()
	if err := files.SetRoot(tmpDir); err != nil {
		t.Fatal(err)
	}
	fpath := filepath.Join(tmpDir, "server.log")
	_ = os.WriteFile(fpath, []byte("Started archangeld daemon\nReady for WireGuard peers\n"), 0644)

	// 1. Unauthenticated request -> 401
	reqUnauth := httptest.NewRequest("GET", "/api/v1/files/list?path="+tmpDir, nil)
	recUnauth := httptest.NewRecorder()
	router.ServeHTTP(recUnauth, reqUnauth)
	if recUnauth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", recUnauth.Code)
	}

	// 2. Authenticated list request -> 200
	reqList := httptest.NewRequest("GET", "/api/v1/files/list?path="+tmpDir, nil)
	reqList.Header.Set("X-Archangel-Token", rawToken)
	recList := httptest.NewRecorder()
	router.ServeHTTP(recList, reqList)

	if recList.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recList.Code, recList.Body.String())
	}

	var listing files.DirectoryListing
	if err := json.Unmarshal(recList.Body.Bytes(), &listing); err != nil {
		t.Fatal(err)
	}
	if listing.TotalEntries != 1 || listing.Entries[0].Name != "server.log" {
		t.Fatalf("unexpected listing: %+v", listing)
	}

	// 3. Authenticated read request -> 200
	reqRead := httptest.NewRequest("GET", "/api/v1/files/read?path="+fpath, nil)
	reqRead.Header.Set("X-Archangel-Token", rawToken)
	recRead := httptest.NewRecorder()
	router.ServeHTTP(recRead, reqRead)

	if recRead.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recRead.Code, recRead.Body.String())
	}

	var resp files.FileContentResponse
	if err := json.Unmarshal(recRead.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Lines) != 2 || resp.Lines[0] != "Started archangeld daemon" {
		t.Fatalf("unexpected lines: %v", resp.Lines)
	}
}
