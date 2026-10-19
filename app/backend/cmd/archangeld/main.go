// Command archangeld is Project Archangel's control-plane server: a single
// binary exposing the server's terminal, files, services, resource stats,
// Docker, and OCI instance controls to the Flutter app, reachable only over
// a WireGuard tunnel.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/dwaipayanray95/project-archangel/backend/internal/api"
	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/config"
	"github.com/dwaipayanray95/project-archangel/backend/internal/devices"
	"github.com/dwaipayanray95/project-archangel/backend/internal/docker"
	"github.com/dwaipayanray95/project-archangel/backend/internal/files"
	"github.com/dwaipayanray95/project-archangel/backend/internal/terminal"
	"github.com/dwaipayanray95/project-archangel/backend/internal/tokenstore"
	"github.com/dwaipayanray95/project-archangel/backend/internal/version"
	"github.com/dwaipayanray95/project-archangel/backend/internal/wgpeer"
)

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "version", "-v", "--version":
			fmt.Printf("archangeld v%s\n", version.Version)
			return
		case "gen-token":
			runGenToken()
			return
		case "pair":
			runPair(os.Args[2:])
			return
		case "devices":
			runDevices(os.Args[2:])
			return
		case "unpair":
			runUnpair(os.Args[2:])
			return
		}
	}

	fs := flag.NewFlagSet("archangeld", flag.ExitOnError)
	configPath := fs.String("config", "/etc/archangel/config.yaml", "path to config.yaml")
	// Ignore the error: ExitOnError already handles a bad flag by printing
	// usage and exiting, so there's nothing left to check here.
	_ = fs.Parse(os.Args[1:])

	cfg, err := config.Load(*configPath)
	if err != nil {
		slog.Error("failed to load config", "err", err)
		os.Exit(1)
	}

	filesRoot := cfg.FilesRoot
	if filesRoot == "" {
		// In Hybrid Cockpit model, /home/archangel is the unified user workspace.
		if info, err := os.Stat("/home/archangel"); err == nil && info.IsDir() {
			filesRoot = "/home/archangel"
		}
	}

	if err := files.SetRoot(filesRoot); err != nil {
		slog.Error("failed to set up file browser root", "err", err)
		os.Exit(1)
	}
	if filesRoot == "" {
		slog.Warn("files_root is not set - the Files tab will reject every request until it is")
	} else {
		slog.Info("file browser root configured", "root", files.Root())
	}

	store, err := tokenstore.Load(cfg.TokenStorePath)
	if err != nil {
		slog.Error("failed to load token store", "err", err)
		os.Exit(1)
	}
	if cfg.TokenHash == "" && len(store.Entries()) == 0 {
		slog.Warn("no auth tokens configured yet - every request will be rejected until a device is paired via `archangeld pair`")
	}

	// Re-reads tokens.json from disk on every check rather than trusting
	// the copy loaded at startup. `archangeld pair` runs as a one-shot CLI
	// command against the *file*, completely independent of this
	// long-running process - without this, every device paired while the
	// server is already running (i.e. every real-world use of `pair`)
	// would 401 until the service was manually restarted. This is a tiny
	// JSON file checked at most once per new WebSocket/request, so the
	// extra disk read is not worth the complexity of a cache + reload
	// signal for a single-user personal tool.
	verify := auth.Verifier(func(hash string) (string, bool) {
		if cfg.TokenHash != "" && subtle.ConstantTimeCompare([]byte(hash), []byte(cfg.TokenHash)) == 1 {
			return "legacy", true
		}
		current, err := tokenstore.Load(cfg.TokenStorePath)
		if err != nil {
			slog.Error("failed to reload token store", "err", err)
			return store.Lookup(hash) // fall back to the startup snapshot rather than locking everyone out
		}
		return current.Lookup(hash)
	})

	// Terminal sessions live in a tmux server outside the service sandbox;
	// see internal/terminal/tmux.go.
	terminal.SetSocketPath(cfg.TerminalSocket)
	// New containers publish "host:container" ports on the WireGuard
	// address only, unless the caller names a public IP explicitly.
	docker.SetPrivateBindIP(cfg.BindAddr)
	devices.Configure(cfg.TokenStorePath, *configPath)

	router := api.NewRouter(verify)

	srv := &http.Server{
		Addr:    cfg.Addr(),
		Handler: router,
		// Guards the handshake phase only (Slowloris-class protection) -
		// once a connection is upgraded to a WebSocket it's hijacked out of
		// net/http's management, so this can't cut off a live terminal
		// session.
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Run the server in the background so the main goroutine can wait for a
	// shutdown signal instead.
	serveErr := make(chan error, 1)
	go func() {
		slog.Info("archangeld starting", "addr", cfg.Addr())
		serveErr <- srv.ListenAndServe()
	}()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	select {
	case err := <-serveErr:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server exited", "err", err)
			os.Exit(1)
		}
	case <-ctx.Done():
		slog.Info("shutting down")

		// WebSocket connections are hijacked out of net/http's request
		// tracking once upgraded, so srv.Shutdown alone would never close
		// or even notice them - close them explicitly first so their PTY
		// child processes get killed and reaped instead of orphaned.
		terminal.CloseAll()

		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("graceful shutdown failed", "err", err)
		}
	}
}

// runGenToken generates a fresh auth token, prints it once (the only time
// it's ever shown in plaintext), and prints the config line to paste into
// config.yaml. It deliberately does not write the config file itself -
// the operator should see and confirm the hash going into place.
func runGenToken() {
	token, hash, err := auth.GenerateToken()
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to generate token:", err)
		os.Exit(1)
	}

	fmt.Println("New Archangel API token (shown once, save it now):")
	fmt.Println()
	fmt.Println("  " + token)
	fmt.Println()
	fmt.Println("Add this line to /etc/archangel/config.yaml:")
	fmt.Println()
	fmt.Printf("  token_hash: %q\n", hash)
	fmt.Println()
	fmt.Println("Pair this token into the Flutter app - it is never stored in plaintext on the server.")
}

// pairingBundle is the single blob the app needs to configure both the
// WireGuard tunnel and the archangeld connection for one device. It's
// base64(JSON)-encoded as a single copy-pasteable string, and - on
// platforms with a camera - the same string encoded as a QR code.
type pairingBundle struct {
	V     int             `json:"v"`
	Name  string          `json:"name"`
	Host  string          `json:"host"`
	Token string          `json:"token"`
	WG    pairingBundleWG `json:"wg"`
}

type pairingBundleWG struct {
	PrivateKey      string   `json:"private_key"`
	Address         string   `json:"address"`
	ServerPublicKey string   `json:"server_public_key"`
	Endpoint        string   `json:"endpoint"`
	AllowedIPs      []string `json:"allowed_ips"`
}

// runPair implements `archangeld pair <device-name> [--qr]`: generates a
// fresh WireGuard keypair and archangeld token for one new device, adds it
// as a live WireGuard peer (persisted to wg0.conf too), and prints one
// bundle the app can use to configure itself in a single step - replacing
// the old flow of SSHing in to run `gen-token`, hand-copying a wg-quick
// config, and typing in the server's tunnel IP by hand.
//
// Must be run as a user who can write /etc/wireguard and run `wg set`
// (i.e. via sudo), same as infra/scripts/wireguard_setup.sh.
func runPair(args []string) {
	fs := flag.NewFlagSet("pair", flag.ExitOnError)
	configPath := fs.String("config", "/etc/archangel/config.yaml", "path to config.yaml")
	asQR := fs.Bool("qr", false, "also print the bundle as an ASCII QR code (needs qrencode)")
	rawOutput := fs.Bool("raw", false, "print only the bare bundle string, no preamble/trailer text - for scripts/automation (e.g. the in-app setup wizard) parsing stdout")

	// Go's flag package stops parsing at the first non-flag argument, so
	// `pair <device-name> --raw` (device name before the flags - the
	// order this command's own usage string below documents, and the
	// order the setup wizard's VpsSetupService._pair calls it in) would
	// otherwise leave BOTH the device name and --raw unconsumed as
	// "positional" args, always failing the len(rest) != 1 check below
	// no matter what the device name is. Partition flags out from the
	// positional device-name argument first so it can appear anywhere
	// relative to the flags, matching how most real CLIs behave.
	flagArgs, positional := splitArgs(args)
	_ = fs.Parse(flagArgs)

	if len(positional) != 1 || positional[0] == "" {
		fmt.Fprintln(os.Stderr, "usage: archangeld pair <device-name> [--qr] [--raw]")
		os.Exit(1)
	}
	name := positional[0]
	if err := tokenstore.ValidateDeviceName(name); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if os.Geteuid() != 0 {
		fmt.Fprintf(os.Stderr, "pair must run as root (it adds a WireGuard peer) - try: sudo archangeld pair %q\n", name)
		os.Exit(1)
	}

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to load config:", err)
		os.Exit(1)
	}
	if cfg.PublicEndpoint == "" {
		fmt.Fprintln(os.Stderr, "config.yaml has no public_endpoint set (e.g. \"203.0.113.5:51820\") - required for `pair` so new devices know where to dial in.")
		os.Exit(1)
	}

	// Check for a duplicate name up front: by the time the token store is
	// written the WireGuard peer would already exist, leaving an orphan.
	store, err := tokenstore.Load(cfg.TokenStorePath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to load the token store:", err)
		os.Exit(1)
	}
	if _, exists := store.Find(name); exists {
		fmt.Fprintf(os.Stderr, "a device named %q already exists - pick another name or `archangeld unpair %s` first.\n", name, name)
		os.Exit(1)
	}

	serverPubKey, listenPort, err := wgpeer.ServerInfo(cfg.WgDir, cfg.WgInterface)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to read this server's WireGuard identity:", err)
		os.Exit(1)
	}
	_ = listenPort // already baked into cfg.PublicEndpoint

	ip, err := wgpeer.NextFreeIP(cfg.WgDir, cfg.WgInterface, cfg.WgSubnet)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to pick a free tunnel address:", err)
		os.Exit(1)
	}

	devicePrivKey, devicePubKey, err := wgpeer.GenerateKeypair()
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to generate a WireGuard keypair:", err)
		os.Exit(1)
	}

	if err := wgpeer.AddPeer(cfg.WgDir, cfg.WgInterface, name, devicePubKey, ip); err != nil {
		fmt.Fprintln(os.Stderr, "failed to add the new WireGuard peer:", err)
		os.Exit(1)
	}

	token, hash, err := auth.GenerateToken()
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to generate an auth token:", err)
		os.Exit(1)
	}

	if err := store.Add(name, hash, devicePubKey, ip); err != nil {
		fmt.Fprintln(os.Stderr, "failed to save the new device's token:", err)
		os.Exit(1)
	}

	bundle := pairingBundle{
		V:     1,
		Name:  name,
		Host:  cfg.Addr(),
		Token: token,
		WG: pairingBundleWG{
			PrivateKey:      devicePrivKey,
			Address:         ip + "/32",
			ServerPublicKey: serverPubKey,
			Endpoint:        cfg.PublicEndpoint,
			AllowedIPs:      []string{cfg.BindAddr + "/32"},
		},
	}

	raw, err := json.Marshal(bundle)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to encode pairing bundle:", err)
		os.Exit(1)
	}
	encoded := base64.StdEncoding.EncodeToString(raw)

	if *rawOutput {
		fmt.Println(encoded)
	} else {
		fmt.Printf("Paired %q at %s. Pairing bundle (shown once - the private key and token aren't stored in plaintext anywhere else):\n\n", name, ip)
		fmt.Println(encoded)
		fmt.Println()
		fmt.Println("Paste this into Archangel's pairing screen (Settings, or the Terminal tab if unpaired).")
	}

	if *asQR {
		qr := exec.Command("qrencode", "-t", "ansiutf8")
		qr.Stdin = strings.NewReader(encoded)
		qr.Stdout = os.Stdout
		qr.Stderr = os.Stderr
		if err := qr.Run(); err != nil {
			fmt.Fprintln(os.Stderr, "\nfailed to render QR code (is qrencode installed?):", err)
		}
	}
}

// splitArgs partitions CLI args into flag arguments and positional ones, so
// the positional argument (device name) may appear before or after the
// flags - Go's flag package stops at the first non-flag argument.
func splitArgs(args []string) (flagArgs, positional []string) {
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-config" || a == "--config":
			flagArgs = append(flagArgs, a)
			if i+1 < len(args) {
				i++
				flagArgs = append(flagArgs, args[i])
			}
		case strings.HasPrefix(a, "-"):
			flagArgs = append(flagArgs, a)
		default:
			positional = append(positional, a)
		}
	}
	return flagArgs, positional
}

// runDevices implements `archangeld devices`: lists paired devices (name,
// created, tunnel IP). Only reads tokens.json, so no root needed beyond
// being able to read that file.
func runDevices(args []string) {
	fs := flag.NewFlagSet("devices", flag.ExitOnError)
	configPath := fs.String("config", "/etc/archangel/config.yaml", "path to config.yaml")
	flagArgs, _ := splitArgs(args)
	_ = fs.Parse(flagArgs)

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to load config:", err)
		os.Exit(1)
	}
	store, err := tokenstore.Load(cfg.TokenStorePath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to load the token store:", err)
		os.Exit(1)
	}
	entries := store.Entries()
	if len(entries) == 0 {
		fmt.Println("No paired devices.")
		return
	}
	fmt.Printf("%-32s  %-20s  %s\n", "NAME", "CREATED", "TUNNEL IP")
	for _, e := range entries {
		ip := e.TunnelIP
		if ip == "" {
			ip = "-"
		}
		fmt.Printf("%-32s  %-20s  %s\n", e.Name, e.CreatedAt.Format("2006-01-02 15:04"), ip)
	}
}

// runUnpair implements `archangeld unpair <name>`: revokes a device by
// deleting its token (so the API rejects it immediately) and then removing
// its WireGuard peer, live and from wg0.conf. Must run as root - the
// in-app "revoke device" button reaches it through `sudo -n`.
func runUnpair(args []string) {
	fs := flag.NewFlagSet("unpair", flag.ExitOnError)
	configPath := fs.String("config", "/etc/archangel/config.yaml", "path to config.yaml")
	flagArgs, positional := splitArgs(args)
	_ = fs.Parse(flagArgs)

	if len(positional) != 1 || positional[0] == "" {
		fmt.Fprintln(os.Stderr, "usage: archangeld unpair <device-name>")
		os.Exit(1)
	}
	name := positional[0]

	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "unpair must run as root (it edits the WireGuard config) - try: sudo archangeld unpair", name)
		os.Exit(1)
	}

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to load config:", err)
		os.Exit(1)
	}
	store, err := tokenstore.Load(cfg.TokenStorePath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to load the token store:", err)
		os.Exit(1)
	}
	entry, ok := store.Find(name)
	if !ok {
		fmt.Fprintf(os.Stderr, "no paired device named %q\n", name)
		os.Exit(1)
	}

	// Token first: that's what actually shuts the API door, and it must
	// happen even if the WireGuard step below fails.
	if err := store.Remove(name); err != nil {
		fmt.Fprintln(os.Stderr, "failed to remove the device's token:", err)
		os.Exit(1)
	}

	if entry.WgPublicKey == "" {
		fmt.Fprintf(os.Stderr, "Removed %q's token, but no WireGuard public key was recorded for it (paired before key tracking) - remove its [Peer] block from %s/%s.conf by hand.\n", name, cfg.WgDir, cfg.WgInterface)
		return
	}
	if err := wgpeer.RemovePeer(cfg.WgDir, cfg.WgInterface, entry.WgPublicKey); err != nil {
		fmt.Fprintf(os.Stderr, "Removed %q's token, but removing its WireGuard peer failed: %v\n", name, err)
		os.Exit(1)
	}
	fmt.Printf("Unpaired %q (token and WireGuard peer removed).\n", name)
}
