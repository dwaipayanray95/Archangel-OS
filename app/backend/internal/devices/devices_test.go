package devices

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/tokenstore"
)

func setup(t *testing.T) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "tokens.json")
	s, _ := tokenstore.Load(path)
	if err := s.Add("phone", "secrethash1", "pk1", "10.10.0.2"); err != nil {
		t.Fatal(err)
	}
	if err := s.Add("laptop", "secrethash2", "pk2", "10.10.0.3"); err != nil {
		t.Fatal(err)
	}
	Configure(path, "/etc/archangel/config.yaml")
}

func TestListMarksCurrentAndHidesHashes(t *testing.T) {
	setup(t)
	req := httptest.NewRequest("GET", "/api/v1/devices", nil)
	req = req.WithContext(auth.WithDeviceName(req.Context(), "laptop"))
	rec := httptest.NewRecorder()
	ListHandler(rec, req)

	if strings.Contains(rec.Body.String(), "secrethash") || strings.Contains(rec.Body.String(), "pk1") {
		t.Errorf("response leaks secrets: %s", rec.Body.String())
	}
	var got []Device
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil || len(got) != 2 {
		t.Fatalf("body = %s (%v)", rec.Body.String(), err)
	}
	if got[0].Current || !got[1].Current || got[1].Name != "laptop" {
		t.Errorf("current flags wrong: %+v", got)
	}
}

func TestDeleteRefusesSelfUnlessConfirmed(t *testing.T) {
	setup(t)
	var unpaired []string
	old := unpair
	unpair = func(name string) error { unpaired = append(unpaired, name); return nil }
	defer func() { unpair = old }()

	do := func(target, query, caller string) int {
		req := httptest.NewRequest("DELETE", "/api/v1/devices/x"+query, nil)
		req.SetPathValue("name", target)
		req = req.WithContext(auth.WithDeviceName(req.Context(), caller))
		rec := httptest.NewRecorder()
		DeleteHandler(rec, req)
		return rec.Code
	}

	if c := do("laptop", "", "laptop"); c != http.StatusConflict || len(unpaired) != 0 {
		t.Errorf("self delete: code=%d unpaired=%v", c, unpaired)
	}
	if c := do("phone", "", "laptop"); c != http.StatusOK || len(unpaired) != 1 || unpaired[0] != "phone" {
		t.Errorf("other delete: code=%d unpaired=%v", c, unpaired)
	}
	if c := do("laptop", "?self=true", "laptop"); c != http.StatusOK || len(unpaired) != 2 {
		t.Errorf("confirmed self delete: code=%d unpaired=%v", c, unpaired)
	}
	if c := do("ghost", "", "laptop"); c != http.StatusNotFound {
		t.Errorf("unknown: code=%d", c)
	}
	if c := do("bad\nname", "", "laptop"); c != http.StatusBadRequest {
		t.Errorf("invalid: code=%d", c)
	}
}
