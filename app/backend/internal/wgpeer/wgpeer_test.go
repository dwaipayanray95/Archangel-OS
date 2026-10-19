package wgpeer

import "testing"

const sampleConf = `[Interface]
Address = 10.10.0.1/24
PrivateKey = SERVERPRIV
ListenPort = 51820

[Peer]
# phone
PublicKey = PUBPHONE=
AllowedIPs = 10.10.0.2/32

[Peer]
# laptop
PublicKey = PUBLAPTOP=
AllowedIPs = 10.10.0.3/32

[Peer]
# tablet
PublicKey = PUBTABLET=
AllowedIPs = 10.10.0.4/32
`

func TestRemovePeerFromConfMiddle(t *testing.T) {
	got, ok := RemovePeerFromConf(sampleConf, "PUBLAPTOP=")
	if !ok {
		t.Fatal("expected a removal")
	}
	want := `[Interface]
Address = 10.10.0.1/24
PrivateKey = SERVERPRIV
ListenPort = 51820

[Peer]
# phone
PublicKey = PUBPHONE=
AllowedIPs = 10.10.0.2/32

[Peer]
# tablet
PublicKey = PUBTABLET=
AllowedIPs = 10.10.0.4/32
`
	if got != want {
		t.Errorf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestRemovePeerFromConfLastAndFirst(t *testing.T) {
	got, ok := RemovePeerFromConf(sampleConf, "PUBTABLET=")
	if !ok {
		t.Fatal("expected a removal")
	}
	if want := sampleConf[:len(sampleConf)-len("\n[Peer]\n# tablet\nPublicKey = PUBTABLET=\nAllowedIPs = 10.10.0.4/32\n")] + ""; got != want {
		t.Errorf("last-peer removal:\n%q\nwant\n%q", got, want)
	}
	got, ok = RemovePeerFromConf(sampleConf, "PUBPHONE=")
	if !ok || got == sampleConf {
		t.Fatal("expected first peer removal")
	}
	for _, s := range []string{"PUBPHONE=", "# phone", "10.10.0.2"} {
		if contains(got, s) {
			t.Errorf("result still contains %q", s)
		}
	}
	for _, s := range []string{"[Interface]", "PUBLAPTOP=", "PUBTABLET="} {
		if !contains(got, s) {
			t.Errorf("result lost %q", s)
		}
	}
}

func TestRemovePeerFromConfCommentAboveHeader(t *testing.T) {
	conf := "[Interface]\nPrivateKey = X\n\n# phone\n[Peer]\nPublicKey = K1=\nAllowedIPs = 10.10.0.2/32\n"
	got, ok := RemovePeerFromConf(conf, "K1=")
	if !ok || got != "[Interface]\nPrivateKey = X\n" {
		t.Errorf("got %q, %v", got, ok)
	}
}

func TestRemovePeerFromConfNotFound(t *testing.T) {
	got, ok := RemovePeerFromConf(sampleConf, "NOPE=")
	if ok || got != sampleConf {
		t.Error("unknown key must leave conf untouched")
	}
	// A key mentioned only in a comment or other field must not match.
	if _, ok := RemovePeerFromConf("[Peer]\n# PUBX=\nPublicKey = OTHER=\n", "PUBX="); ok {
		t.Error("matched key in a comment")
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
