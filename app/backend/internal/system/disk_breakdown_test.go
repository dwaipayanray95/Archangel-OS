package system

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestGetDiskBreakdown(t *testing.T) {
	b := GetDiskBreakdown()
	if len(b.Folders) == 0 {
		t.Fatal("expected non-empty folders breakdown")
	}
	if len(b.Packages) == 0 {
		t.Fatal("expected non-empty packages breakdown")
	}

	if b.Folders[0].Bytes == 0 {
		t.Error("expected positive bytes for top folder")
	}
}

func TestDiskBreakdownHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/system/disk-breakdown", nil)
	w := httptest.NewRecorder()

	DiskBreakdownHandler(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", w.Code)
	}

	if ct := w.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("expected application/json, got %s", ct)
	}
}
