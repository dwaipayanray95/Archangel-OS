# Archangel Backend (`archangeld`)

The Go control-plane server: one static binary that gives the Flutter app a terminal, files, system stats, Docker control, systemd services, and device management. It listens only on the WireGuard tunnel address, never the public internet.

New to Archangel? Start with the [user docs](../../docs/getting-started.md). This page is for people working on the backend.

## What it does

- **Auth:** per-device tokens (SHA-256 hashes in `tokens.json`), plus an optional legacy shared token.
- **Terminal:** a real PTY over WebSocket, backed by persistent tmux sessions.
- **System:** CPU/memory/disk/network metrics, process list with kill/renice, live stats stream, reboot.
- **Files:** a browser jailed to `files_root` (read-only: list, preview, download).
- **Docker:** list, run, start/stop/restart/remove containers, live logs. Ports are private by default.
- **DevOps (Services):** an allowlist of systemd services, timers, Caddy web addresses, deploy scripts.
- **Devices:** list, create (pair) and revoke paired devices.
- **Admin mode:** whether the `archangel` user has passwordless sudo.

Everything is real (no mock data).

## Versioning

There is one version for the whole product. The backend takes the semver part of `version:` in [`app/frontend/pubspec.yaml`](../frontend/pubspec.yaml) (for `0.8.0+2` that is `0.8.0`) and bakes it in at build time with `-ldflags` (see `Makefile` and `internal/version`). It is shown by `archangeld version` (for example `archangeld v0.8.0`) and returned by `/api/v1/health`. The app compares it with the latest release to detect when an update is available. Override with `make build-linux-amd64 VERSION=1.2.3`; a plain `go build` reports `0.0.0-dev`.

## API

All routes except `/api/v1/health` need a token: header `X-Archangel-Token`, or `?token=` on WebSocket handshakes. Routes live in [`internal/api/router.go`](internal/api/router.go).

| Route | What it does |
|---|---|
| `GET /api/v1/health` | Liveness check, no auth. Returns `{"status":"ok","version":"..."}`. |
| `GET /ws/terminal?session=<name>` | Interactive shell over WebSocket (JSON frames, see `internal/wsproto`). Default session `main`. |
| `GET /api/v1/terminal/sessions` | List tmux sessions. |
| `DELETE /api/v1/terminal/sessions/{name}` | End a tmux session. |
| `GET /api/v1/devices` | List paired devices (names, dates, tunnel IPs; never token hashes). The caller is flagged `current`. |
| `POST /api/v1/devices` | Pair a new device (`{"name": "..."}`). Returns the one-time pairing bundle. Needs Admin mode. |
| `DELETE /api/v1/devices/{name}` | Revoke a device (token + WireGuard peer). Needs Admin mode. |
| `GET /api/v1/system/admin-mode` | Whether Admin mode is on. |
| `POST /api/v1/system/admin-mode` | Only `{"enabled": false}` works. `true` returns 409 by design. |
| `GET /api/v1/system/metrics` | CPU, memory, disk, network, uptime. |
| `GET /api/v1/system/processes` | Process list. |
| `POST /api/v1/system/processes/{pid}/kill` | Kill a process. |
| `POST /api/v1/system/processes/{pid}/renice` | Change a process's priority. |
| `POST /api/v1/system/reboot` | Reboot the server. Needs Admin mode. |
| `GET /ws/stats` | Live metrics stream (interval chosen by the client). |
| `GET /api/v1/files/list?path=` | List a directory inside `files_root`. |
| `GET /api/v1/files/read?path=&lines=` | Preview a text file. |
| `GET /api/v1/files/download?path=` | Download a file. |
| `GET /api/v1/docker/containers` | List containers. |
| `POST /api/v1/docker/containers/run` | Create and start a container. |
| `POST /api/v1/docker/containers/{id}/{action}` | `start`, `stop`, `restart`, or `remove`. |
| `GET /ws/docker/containers/{id}/logs` | Live container logs. |
| `GET /api/v1/devops/services` | List allowlisted systemd services. |
| `POST /api/v1/devops/services/{name}/{action}` | `start`, `stop`, `restart` (needs Admin mode). SSH, WireGuard and archangel itself can't be stopped. |
| `GET /api/v1/devops/scheduled` | List systemd timers. |
| `POST /api/v1/devops/scheduled/{name}/run` | Run a timer's job now. |
| `GET /api/v1/devops/proxy` | List Caddy web addresses. |
| `POST /api/v1/devops/proxy/{domain}/test` | Check a web address. |
| `GET /api/v1/devops/deployments` | List deploy scripts. |
| `POST /api/v1/devops/deployments` | Create or update a script. |
| `GET /api/v1/devops/deployments/{name}/content` | Read a script. |
| `DELETE /api/v1/devops/deployments/{name}` | Delete a script. |
| `POST /api/v1/devops/deployments/{name}/run` | Run a script. |

## Command line

```bash
archangeld                      # run the server (default: -config /etc/archangel/config.yaml)
archangeld version              # also -v, --version
archangeld gen-token            # print a new token + the token_hash line (legacy single-token setup)
sudo archangeld pair <name> [--qr] [--raw]
archangeld devices              # list paired devices
sudo archangeld unpair <name>   # revoke a device
```

| Command | Notes |
|---|---|
| `pair` | Needs root and `public_endpoint` in the config. Picks the next free tunnel IP, makes a WireGuard keypair, adds the peer live and in `wg0.conf`, makes a token, and prints one base64 bundle the app can use. `--qr` also prints a QR (needs `qrencode`). `--raw` prints only the bundle (what the setup wizard parses). The name must be unused. |
| `devices` | Reads `tokens.json`. |
| `unpair` | Needs root. Deletes the token first (closes the API door), then the WireGuard peer. |
| `gen-token` | Does not write the config; you paste the `token_hash` line yourself. |

## Config

See [`config.example.yaml`](config.example.yaml). The important fields:

| Field | Meaning |
|---|---|
| `bind_addr` | Must be the WireGuard IP (e.g. `10.10.0.1`). `0.0.0.0` or empty is rejected. `127.0.0.1` is fine for local dev. |
| `port` | Default 8443. |
| `files_root` | Folder the Files tab is limited to. Empty means every Files request is rejected. The server falls back to `/home/archangel` if that exists. |
| `token_store_path` | Default `/etc/archangel/tokens.json`. |
| `public_endpoint` | `host:port` of the server's WireGuard, for `pair`. |
| `terminal_socket` | tmux socket path. Default `/home/archangel/.archangel/tmux.sock`. |

## Admin mode and the sandbox

`archangeld` runs as the unprivileged `archangel` user under [`infra/scripts/archangel.service`](../../infra/scripts/archangel.service) with these relevant settings:

- `NoNewPrivileges=false` (so `sudo` works)
- `ProtectSystem=full`, `PrivateTmp=true`
- `ReadWritePaths=/home/archangel /opt/archangel -/srv/deploy`, `ReadOnlyPaths=/etc/archangel`
- resource caps: `MemoryMax=150M`, `MemoryHigh=120M`, `CPUQuota=50%`, `TasksMax=100`

**Admin mode** is a sudoers drop-in, `/etc/sudoers.d/archangel`, containing `archangel ALL=(ALL) NOPASSWD: ALL`. The setup wizard writes it. All code that needs root goes through `internal/adminmode` (`Run`), which always uses `sudo -n` (never prompts) and returns one clear error, "Admin mode is off - this action needs it", when sudo refuses.

**Sandbox escape.** `sudo` alone isn't enough: children of the service inherit its mount namespace, where `/etc` is read-only even for root. So `adminmode.Run` wraps the command in `systemd-run --quiet --wait --pipe --collect --service-type=exec -- <cmd>`. PID 1 then runs it as a transient unit outside the sandbox. (Without `systemd-run`, e.g. a non-systemd dev box, it runs the bare command.)

**The API can only turn Admin mode off.** `POST /api/v1/system/admin-mode` with `enabled: true` returns 409. Turning it on needs the owner's SSH key; the app does it over SSH. So a leaked token can drop privileges but never regain them. When Admin mode is on, a token is effectively root. See [docs/security.md](../../docs/security.md).

## Terminal design (tmux)

The shell used to be a child of `archangeld`, so it died on every service restart and inherited the sandbox. Now:

- Shells live in a **tmux server** started with `systemd-run --user --unit=archangel-tmux` under the `archangel` user's systemd user manager (a different cgroup and mount namespace than the service). This needs `tmux` and `dbus-user-session`, and lingering (`loginctl enable-linger archangel`, done by the unit's `ExecStartPre`).
- The WebSocket PTY just runs a tmux **client** (`tmux -S <socket> new-session -A -s <name>`). Closing it or restarting `archangeld` leaves the shells alive.
- The socket path is explicit (`terminal_socket`) because `PrivateTmp=true` would hide a `/tmp` socket.
- Session names: 1 to 32 characters of `A-Z a-z 0-9 _ -`. Max 3 concurrent connections. Idle connections close after 10 minutes.
- If tmux can't start, the handler sends an `error` frame ("Persistent sessions unavailable ..., using a temporary shell") and falls back to a plain login shell that dies with the connection.

## Local development

```bash
cp config.example.yaml config.yaml
go run ./cmd/archangeld gen-token   # token + token_hash line to paste into config.yaml
make run
```

`bind_addr` stays `127.0.0.1` for local dev. Set `files_root` to something for the Files routes to work. Tests: `go vet ./...` and `go test ./...` (also `make vet`, `make test`).

Manual WebSocket test (`curl` can't do WebSockets): `brew install websocat`, then
```bash
websocat "ws://10.10.0.1:8443/ws/terminal?token=<your-token>"
```
and send `{"type":"resize","cols":100,"rows":30}`, then `{"type":"stdin","data":"<base64 of command + \n>"}`. You get `stdout` frames back and an `exit` frame when the shell ends.

## Getting a binary onto a server

1. **The in-app setup wizard** (new servers, and updates). It SSHes in, runs the setup scripts, downloads `archangeld` from the latest GitHub release, verifies its SHA-256 against the release's `SHA256SUMS`, installs the systemd unit, and pairs. For updates it backs up the old binary, installs the new one, restarts, waits for the new version to answer `/api/v1/health`, and rolls back automatically if it doesn't. See `app/frontend/lib/services/vps_setup_service.dart`. Updates go over SSH on purpose: the service user can't write its own binary (`/opt/archangel/archangeld` is owned by root), so a leaked token can't replace it.
2. **`deploy.sh`**: builds locally and copies the binary over (`SERVER_HOST=... SERVER_USER=... SSH_KEY=... ./deploy.sh`). Safe to re-run; it won't regenerate an existing config.
3. **A release tag**: see below.

## Uninstalling

[`infra/scripts/uninstall.sh [app_port] [wg_port]`](../../infra/scripts/uninstall.sh) stops and removes the `archangel` service, the binary, `/etc/archangel`, WireGuard (interface, keys, config), the firewall rules for both ports, and the `archangel` user. It leaves what `baseline_setup.sh` installed (packages, swap, Docker, Caddy, tmux, ufw basics). Safe to re-run. In the app: Settings, Danger zone, "Uninstall backend".

## Releases

One workflow, [`.github/workflows/release.yml`](../../.github/workflows/release.yml), builds the server program and all the apps for every release, tagged `vX.Y.Z` from the pubspec version. Start it from the Actions tab (or push the tag). Every run publishes `version-manifest.json`, which the app reads to show "update available". See [CONTRIBUTING.md](../../CONTRIBUTING.md#releases).
