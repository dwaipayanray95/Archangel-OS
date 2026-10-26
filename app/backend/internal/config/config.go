// Package config loads the Archangel backend's configuration: where to bind,
// where the auth token hash lives, and other server-wide settings.
package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	// BindAddr MUST be the WireGuard interface IP (e.g. "10.10.0.1"), never
	// "0.0.0.0" or a public IP. This is what keeps the API unreachable from
	// the public internet - the single most important setting in this file.
	// UFW closing the port publicly is the second layer; this is the first.
	BindAddr string `yaml:"bind_addr"`
	Port     int    `yaml:"port"`

	// TokenHash is a legacy single shared-token hash (SHA-256, hex-encoded),
	// never the plaintext token itself. Optional - kept only for whatever
	// was paired before per-device tokens (TokenStorePath below) existed.
	// New devices are paired via `archangeld pair`, which only writes to
	// the token store.
	TokenHash string `yaml:"token_hash"`

	// TokenStorePath is where per-device token hashes live, one entry per
	// device paired via `archangeld pair`. See internal/tokenstore.
	TokenStorePath string `yaml:"token_store_path"`

	// FilesRoot is the directory the file browser is jailed to (Milestone 2).
	FilesRoot string `yaml:"files_root"`

	// UploadMaxBytes caps a single Files upload. 0 means the default (2 GiB).
	UploadMaxBytes int64 `yaml:"upload_max_bytes"`

	// WgDir is where WireGuard's config lives (wg0.conf, peer keys) -
	// matches infra/scripts/wireguard_setup.sh's WG_DIR.
	WgDir string `yaml:"wg_dir"`
	// WgInterface is the WireGuard interface name (matches wg0.conf).
	WgInterface string `yaml:"wg_interface"`
	// WgSubnet is the WireGuard tunnel subnet's first three octets (server
	// is always .1) - matches wireguard_setup.sh's WG_SUBNET.
	WgSubnet string `yaml:"wg_subnet"`
	// PublicEndpoint is this server's public "host:port" for WireGuard
	// (e.g. "203.0.113.5:51820") - what `archangeld pair` puts in a new
	// device's config so it knows where to dial in from outside the
	// tunnel. Required for `archangeld pair` to work; unused otherwise.
	PublicEndpoint string `yaml:"public_endpoint"`

	// TerminalSocket is the tmux server socket the Terminal tab's
	// persistent sessions use. It must be an explicit path (not tmux's
	// default under /tmp) because archangel.service has PrivateTmp=true, so
	// a /tmp socket would be invisible to the tmux server, which runs
	// outside the service's sandbox. Its directory is created 0700.
	TerminalSocket string `yaml:"terminal_socket"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config %s: %w", path, err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config %s: %w", path, err)
	}

	if cfg.BindAddr == "" || cfg.BindAddr == "0.0.0.0" {
		return nil, fmt.Errorf("bind_addr must be set to the WireGuard interface IP, not empty or 0.0.0.0 (got %q)", cfg.BindAddr)
	}
	if cfg.Port == 0 {
		cfg.Port = 8443
	}
	if cfg.TokenStorePath == "" {
		cfg.TokenStorePath = "/etc/archangel/tokens.json"
	}
	if cfg.WgDir == "" {
		cfg.WgDir = "/etc/wireguard"
	}
	if cfg.WgInterface == "" {
		cfg.WgInterface = "wg0"
	}
	if cfg.WgSubnet == "" {
		cfg.WgSubnet = "10.10.0"
	}
	if cfg.TerminalSocket == "" {
		cfg.TerminalSocket = "/home/archangel/.archangel/tmux.sock"
	}

	return &cfg, nil
}

func (c *Config) Addr() string {
	return fmt.Sprintf("%s:%d", c.BindAddr, c.Port)
}
