package tokenstore

import (
	"path/filepath"
	"testing"
)

func TestValidateDeviceName(t *testing.T) {
	good := []string{"a", "iPhone 15", "pixel_8.pro-2", "0day"}
	for _, n := range good {
		if err := ValidateDeviceName(n); err != nil {
			t.Errorf("ValidateDeviceName(%q) = %v, want ok", n, err)
		}
	}
	bad := []string{"", " lead", "-lead", "new\nline", "a\n[Peer]", "trail\n", "semi;colon", "has/slash",
		"0123456789012345678901234567890123"}
	for _, n := range bad {
		if err := ValidateDeviceName(n); err == nil {
			t.Errorf("ValidateDeviceName(%q) = nil, want error", n)
		}
	}
}

func TestAddRemoveRenameRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tokens.json")
	s, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	// chownGroupToMatch needs the dir's own group, which we have in a tempdir.
	if err := s.Add("phone", "h1", "pub1", "10.10.0.2"); err != nil {
		t.Fatalf("Add: %v", err)
	}
	if err := s.Add("laptop", "h2", "pub2", "10.10.0.3"); err != nil {
		t.Fatalf("Add: %v", err)
	}
	if err := s.Add("phone", "h3", "", ""); err == nil {
		t.Error("duplicate Add should fail")
	}
	if err := s.Add("bad\nname", "h4", "", ""); err == nil {
		t.Error("Add with newline name should fail")
	}

	if n, ok := s.Lookup("h2"); !ok || n != "laptop" {
		t.Errorf("Lookup(h2) = %q,%v", n, ok)
	}
	if _, ok := s.Lookup("nope"); ok {
		t.Error("Lookup of unknown hash should fail")
	}

	if err := s.Rename("phone", "iphone"); err != nil {
		t.Fatalf("Rename: %v", err)
	}
	if err := s.Rename("iphone", "laptop"); err == nil {
		t.Error("Rename onto an existing name should fail")
	}
	if err := s.Rename("ghost", "x"); err == nil {
		t.Error("Rename of unknown device should fail")
	}

	reloaded, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	e, ok := reloaded.Find("iphone")
	if !ok || e.WgPublicKey != "pub1" || e.TunnelIP != "10.10.0.2" {
		t.Errorf("reloaded entry = %+v, %v", e, ok)
	}

	if err := reloaded.Remove("iphone"); err != nil {
		t.Fatalf("Remove: %v", err)
	}
	if err := reloaded.Remove("iphone"); err == nil {
		t.Error("second Remove should fail")
	}
	again, _ := Load(path)
	if len(again.Entries()) != 1 || again.Entries()[0].Name != "laptop" {
		t.Errorf("entries after remove = %+v", again.Entries())
	}
}
