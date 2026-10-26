package files_test

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dwaipayanray95/project-archangel/backend/internal/api"
	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/files"
)

func TestUploadRouteRequiresAuth(t *testing.T) {
	rawToken := "upload-token"
	expectedHash := auth.HashToken(rawToken)
	router := api.NewRouter(func(h string) (string, bool) { return "test", h == expectedHash })

	tmpDir := t.TempDir()
	if err := files.SetRoot(tmpDir); err != nil {
		t.Fatal(err)
	}
	target := "/api/v1/files/upload?dir=" + files.Root() + "&name=up.txt"

	unauth := httptest.NewRecorder()
	router.ServeHTTP(unauth, httptest.NewRequest("POST", target, strings.NewReader("data")))
	if unauth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", unauth.Code)
	}
	if _, err := os.Stat(filepath.Join(files.Root(), "up.txt")); err == nil {
		t.Fatal("unauthenticated upload wrote a file")
	}

	req := httptest.NewRequest("POST", target, strings.NewReader("data"))
	req.Header.Set("X-Archangel-Token", rawToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}
