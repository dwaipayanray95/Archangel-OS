// Package tokenstore persists per-device auth token hashes, replacing the
// old single-shared-token model (one token_hash in config.yaml) with one
// entry per paired device. Only hashes are ever written to disk, same
// discipline as the legacy token_hash field.
package tokenstore

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
)

type Entry struct {
	Name      string    `json:"name"`
	HashHex   string    `json:"hash"`
	CreatedAt time.Time `json:"created_at"`
	// WgPublicKey and TunnelIP identify the device's WireGuard peer so
	// `archangeld unpair` can remove it. Empty for entries created before
	// these fields existed (omitempty keeps old files byte-compatible).
	WgPublicKey string `json:"wg_public_key,omitempty"`
	TunnelIP    string `json:"tunnel_ip,omitempty"`
}

// validDeviceName: starts alphanumeric, then letters/digits/space/_/./-,
// 1-32 chars. The name is written into wg0.conf as a "# name" comment, so
// anything that could break out of that line (newline especially) must be
// impossible - `$` in Go's RE2 matches only at end of text, but newline is
// excluded from the charset anyway.
var validDeviceName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9 _.-]{0,31}$`)

// ValidateDeviceName reports whether name is acceptable as a device name.
func ValidateDeviceName(name string) error {
	if strings.ContainsAny(name, "\r\n") || !validDeviceName.MatchString(name) {
		return fmt.Errorf("invalid device name %q: use 1-32 letters, digits, spaces, '_', '.' or '-', starting with a letter or digit", name)
	}
	return nil
}

// Store is not safe for concurrent writers - archangeld only ever writes
// from the one-shot `pair` CLI subcommand, never from the long-running
// server process, so this doesn't need locking.
type Store struct {
	path    string
	entries []Entry
}

// Load reads the store at path, or returns an empty store if the file
// doesn't exist yet (the common case before the first device is paired).
func Load(path string) (*Store, error) {
	s := &Store{path: path}

	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading token store %s: %w", path, err)
	}

	if err := json.Unmarshal(data, &s.entries); err != nil {
		return nil, fmt.Errorf("parsing token store %s: %w", path, err)
	}
	return s, nil
}

// Entries returns the currently paired devices. Used only to decide
// whether any auth token exists at all yet, not for anything security
// sensitive.
func (s *Store) Entries() []Entry {
	return s.entries
}

// IsValid reports whether hashHex matches any paired device's token hash,
// using a constant-time comparison per entry so timing can't leak how
// close a guess got.
func (s *Store) IsValid(hashHex string) bool {
	for _, e := range s.entries {
		if subtle.ConstantTimeCompare([]byte(e.HashHex), []byte(hashHex)) == 1 {
			return true
		}
	}
	return false
}

// Lookup returns the name of the device whose token hash matches hashHex
// (constant-time per entry, like IsValid).
func (s *Store) Lookup(hashHex string) (string, bool) {
	for _, e := range s.entries {
		if subtle.ConstantTimeCompare([]byte(e.HashHex), []byte(hashHex)) == 1 {
			return e.Name, true
		}
	}
	return "", false
}

// Find returns the entry with the given name.
func (s *Store) Find(name string) (Entry, bool) {
	for _, e := range s.entries {
		if e.Name == name {
			return e, true
		}
	}
	return Entry{}, false
}

// Add appends a new device entry and persists the store immediately.
// wgPublicKey and tunnelIP record the device's WireGuard peer.
func (s *Store) Add(name, hashHex, wgPublicKey, tunnelIP string) error {
	if err := ValidateDeviceName(name); err != nil {
		return err
	}
	if _, exists := s.Find(name); exists {
		return fmt.Errorf("a device named %q already exists", name)
	}
	s.entries = append(s.entries, Entry{
		Name: name, HashHex: hashHex, CreatedAt: time.Now().UTC(),
		WgPublicKey: wgPublicKey, TunnelIP: tunnelIP,
	})
	return s.save()
}

// Remove deletes the named device and persists the store.
func (s *Store) Remove(name string) error {
	for i, e := range s.entries {
		if e.Name == name {
			s.entries = append(s.entries[:i:i], s.entries[i+1:]...)
			return s.save()
		}
	}
	return fmt.Errorf("no device named %q", name)
}

// Rename changes a device's name and persists the store. Only the token
// store entry changes; the "# name" comment in wg0.conf is left as-is.
func (s *Store) Rename(oldName, newName string) error {
	if err := ValidateDeviceName(newName); err != nil {
		return err
	}
	if _, exists := s.Find(newName); exists {
		return fmt.Errorf("a device named %q already exists", newName)
	}
	for i := range s.entries {
		if s.entries[i].Name == oldName {
			s.entries[i].Name = newName
			return s.save()
		}
	}
	return fmt.Errorf("no device named %q", oldName)
}

func (s *Store) save() error {
	data, err := json.MarshalIndent(s.entries, "", "  ")
	if err != nil {
		return fmt.Errorf("encoding token store: %w", err)
	}

	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return fmt.Errorf("creating token store dir: %w", err)
	}

	// Write to a temp file and rename over the real path so a crash
	// mid-write can never leave a truncated/corrupt store behind.
	tmp := s.path + ".tmp"
	// 0640 (not 0600): `archangeld pair` runs as root (via sudo), but the
	// long-running server process runs as the unprivileged `archangel`
	// system user - a root-only file would be unreadable to it, which is
	// exactly what happened on real hardware (server failed to start with
	// "permission denied" after the first `pair` call). Group-readable,
	// plus chownGroupToMatch below matching the parent directory's group
	// (deploy.sh sets that to the `archangel` group), lets the service
	// read this without making it world-readable.
	if err := os.WriteFile(tmp, data, 0o640); err != nil {
		return fmt.Errorf("writing token store: %w", err)
	}
	if err := chownGroupToMatch(tmp, dir); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("setting token store group ownership: %w", err)
	}
	if err := os.Rename(tmp, s.path); err != nil {
		return fmt.Errorf("saving token store: %w", err)
	}
	return nil
}

// chownGroupToMatch sets path's group ownership to match dir's, leaving
// the owner (uid) untouched. When `pair` runs via sudo, that owner stays
// root - fine, since group-read (0640) is what the archangeld service
// actually needs. A no-op, non-fatal warning path on non-Unix platforms
// doesn't apply here: this package only ever runs on the Linux server.
func chownGroupToMatch(path, dir string) error {
	info, err := os.Stat(dir)
	if err != nil {
		return fmt.Errorf("stat %s: %w", dir, err)
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return fmt.Errorf("could not read %s's group ownership", dir)
	}
	if err := os.Chown(path, -1, int(stat.Gid)); err != nil {
		return fmt.Errorf("chown %s to group %d: %w", path, stat.Gid, err)
	}
	return nil
}
