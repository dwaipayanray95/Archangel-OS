package docker

import (
	"testing"
	"time"
)

func TestParsePortSpec(t *testing.T) {
	cases := []struct {
		in      string
		want    PortSpec
		nilSpec bool
		wantErr bool
	}{
		{in: "", nilSpec: true},
		{in: "80", want: PortSpec{ContainerPort: "80/tcp"}},
		{in: "8080:80", want: PortSpec{ContainerPort: "80/tcp", HostIP: "10.10.0.1", HostPort: "8080"}},
		{in: "8080:53/udp", want: PortSpec{ContainerPort: "53/udp", HostIP: "10.10.0.1", HostPort: "8080"}},
		{in: "0.0.0.0:8080:80", want: PortSpec{ContainerPort: "80/tcp", HostIP: "0.0.0.0", HostPort: "8080"}},
		{in: "127.0.0.1:9000:90/tcp", want: PortSpec{ContainerPort: "90/tcp", HostIP: "127.0.0.1", HostPort: "9000"}},
		{in: "0:80", wantErr: true},
		{in: "70000:80", wantErr: true},
		{in: "8080:abc", wantErr: true},
		{in: "8080:80/sctp", wantErr: true},
		{in: "notanip:8080:80", wantErr: true},
		{in: "1.2.3.4:5:6:7", wantErr: true},
	}
	for _, tc := range cases {
		got, err := ParsePortSpec(tc.in, "10.10.0.1")
		if tc.wantErr {
			if err == nil {
				t.Errorf("ParsePortSpec(%q) = %+v, want error", tc.in, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("ParsePortSpec(%q) error: %v", tc.in, err)
			continue
		}
		if tc.nilSpec {
			if got != nil {
				t.Errorf("ParsePortSpec(%q) = %+v, want nil", tc.in, got)
			}
			continue
		}
		if got == nil || *got != tc.want {
			t.Errorf("ParsePortSpec(%q) = %+v, want %+v", tc.in, got, tc.want)
		}
	}
}

func TestPrivateBindIPFailsClosed(t *testing.T) {
	defer SetPrivateBindIP("")
	SetPrivateBindIP("")
	if got := privateBindIP(); got != "127.0.0.1" {
		t.Errorf("unset privateBindIP = %q, want 127.0.0.1", got)
	}
	SetPrivateBindIP("10.10.0.1")
	if got := privateBindIP(); got != "10.10.0.1" {
		t.Errorf("privateBindIP = %q", got)
	}
}

func TestMergeStats(t *testing.T) {
	now := time.Now()
	s := newStatsCache()
	s.put("fresh", 12.5, 300, "300 MB", now.Add(-2*time.Second))
	s.put("stale", 99, 999, "999 MB", now.Add(-31*time.Second))
	s.put("stopped", 5, 5, "5 MB", now)

	items := []ContainerItem{
		{ID: "fresh", Running: true, MemLabel: "—"},
		{ID: "stale", Running: true, MemLabel: "—"},
		{ID: "unknown", Running: true, MemLabel: "—"},
		{ID: "stopped", Running: false, MemLabel: "—"},
	}
	mergeStats(items, s, now)

	if items[0].CPU != 12.5 || items[0].MemMb != 300 || items[0].MemLabel != "300 MB" {
		t.Errorf("fresh not merged: %+v", items[0])
	}
	for _, i := range []int{1, 2, 3} {
		if items[i].CPU != 0 || items[i].MemLabel != "—" {
			t.Errorf("item %d should be untouched: %+v", i, items[i])
		}
	}

	s.prune(map[string]bool{"fresh": true})
	if _, ok := s.entries["stale"]; ok {
		t.Error("prune kept an entry not in keep set")
	}
}
