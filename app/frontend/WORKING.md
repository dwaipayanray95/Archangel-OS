# Archangel frontend — working notes / handoff

Status snapshot for picking this up cold. Read this before touching
anything — it'll save you from re-discovering things the hard way.

## What this is

A Flutter app (Android/Windows/macOS/Linux from one codebase) that's the
GUI for `archangeld`, a Go backend running on a personal VPS, reachable
only over a WireGuard tunnel. Design source: a Claude Design mockup
(`Archangel.dc.html`, dark cockpit aesthetic) — the design brief and
mockup markup aren't in this repo, only the Flutter implementation of it.

Sibling doc: **`WIREGUARD.md`** in this same folder — read that too, it
has the full per-platform WireGuard status and is more detailed than the
summary below.

## What actually works, verified for real (not just "should work")

- **App shell**: top status bar, sidebar nav (bottom tabs on phone width),
  ⌘K command palette — all 7 sections (Overview, Monitoring, Files,
  Containers, DevOps, Terminal, Settings) render correctly.
- **Terminal ↔ archangeld, end-to-end, for real**: a real PTY executed
  `whoami` and `uname -a` and returned real output over the real
  WebSocket, driving the exact JSON frame protocol `TerminalSession`
  implements.
- **Monitoring ↔ archangeld, for real**: real `/proc`-derived CPU/memory/
  disk metrics and process list, kill/renice both working against a
  real deployed server, with a `/code-review` pass fixing a concurrent
  map write crash, an always-permissive `CheckOrigin`, a fake
  `CPUPercent` that broke sort order, and kill/renice errors that used
  to be silently swallowed.
- **Files ↔ archangeld, for real, and jailed**: list/preview/download
  confined to a configured `files_root` both textually and through
  symlinks (`internal/files/service.go`'s `resolvePath` -
  `filepath.EvalSymlinks` re-validated against the root, not just the
  requested string). Fails closed if `files_root` is unset. The
  sidebar's shortcut list shows the real configured root and its real
  subdirectories - it used to be a hardcoded list of unrelated system
  paths (`/etc`, `/var/log`, ...) that 403'd on anything but a `files_root`
  of `/`, and a failed tap used to stay highlighted as if it had
  succeeded; both fixed.
- **WireGuard state machine on Linux**: real `wireguard_flutter` package,
  real failure path exercised (no `wg`/sudo in that sandbox → surfaced
  correctly as "unsupported" in both the top bar and Settings, no crash).
- **macOS WireGuard, end-to-end, for real** — real device, real
  deployed server, a real Terminal shell session opened over the tunnel
  this app's own custom `wireguard-go`-based backend manages (not a VPN
  client running alongside it — this app *is* the VPN client). Took five
  rounds of real bugs found via actual hardware testing: `wireguard-go`
  daemonizing by default, `disconnect()` killing the wrong process
  (leaked root processes), a UAPI socket permission denial, a Swift
  compile error, and — the one that made "tunnel shows green" not mean
  "traffic can reach the server" — a missing route for the peer's
  address. Full history in `WIREGUARD.md`, including small remaining
  rough edges (an unexplained first-connect-needs-a-reconnect quirk,
  three admin prompts per connect, full-tunnel `0.0.0.0/0` still
  unhandled).
- **In-app VPS setup wizard, end-to-end, for real**: bootstrapped a real
  fresh VPS entirely from the app (baseline, WireGuard, binary download,
  systemd service, pairing) with no manual SSH.
- `flutter analyze`: clean. `flutter test`: 20 passing (4 pre-existing
  failures in `all_sections_test.dart`, unrelated to any of the work
  below - a `FilesService` provider missing from `test_utils.dart`'s
  test harness).

## What's built but NOT verified (no toolchain existed to test it)

The sandbox this was built in is Linux-only — no Android SDK, no Xcode,
no Windows toolchain. Everything below is real, complete code, but
**unverified**:

- **Android**: wiring is correct (`wireguard_flutter`'s real `VpnService`
  backend, `INTERNET` permission added), never run on a device or emulator.
- **Windows**: same — `wireguard_flutter` bundles real `WireGuardNT`
  binaries, app now requests admin elevation on launch (needed to create
  the tunnel service). Never compiled with an actual Windows toolchain.
- **The release pipeline** (`.github/workflows/release.yml`, replacing
  the old manual `build-app.yml`/`release-backend.yml`): one version
  (`version:` in pubspec.yaml), tag `v<semver>`, every run builds the
  backend and all apps and publishes `version-manifest.json` (what
  `UpdateCheckService` reads). Started from Actions or by pushing the
  tag. The new single-version workflow has **never run on GitHub's
  runners** yet.
- **In-app backend updates**: `VpsSetupService.updateBackend()` +
  `BackendUpdateDialog` - backs up the current binary, downloads +
  version-verifies the new one, restarts the service, polls `/health`
  for up to ~20s, and rolls back automatically if the new version never
  comes up. Unit-tested against a fake SSH transport (success path,
  rollback path, pre-install verification-failure path) but never run
  against a real VPS.
- **In-app server uninstall**: `VpsSetupService.uninstall()` +
  `UninstallDialog` (Settings' "Danger zone", visible once paired) -
  uploads and runs `infra/scripts/uninstall.sh` over SSH to stop/remove
  archangeld and tear down WireGuard entirely, gated behind a typed
  confirmation step since it's irreversible; on success also clears the
  app's own pairing/WireGuard state for that server. Unit-tested against
  a fake SSH transport (command sequence, failure surfacing) but never
  run against a real VPS.

## Known gaps / things to do next, roughly in priority order

1. **Run the release pipeline for real** — run "Release Archangel" once
   and confirm the tag, artifacts and `version-manifest.json` come out as
   described in CONTRIBUTING.md.
2. **Android/Windows real-device testing**: nobody has run this app on
   either platform yet. Expect friction — this is genuinely the first
   time this code has met a real toolchain for either. (macOS, and now
   the full backend feature set, are done — see above.)
3. **In-app backend update, against a real VPS**: exercise the actual
   SSH update flow (including a deliberately-broken build, to confirm
   the auto-rollback really works) once a real tagged release exists.
4. **Containers/DevOps are still 100% mock data** (`lib/data/mock_data.dart`)
   - no backend routes exist for them yet.
5. **Terminal is not a full terminal emulator** — `TerminalSession`
   renders raw output, no ANSI/VT100 escape sequence handling. Fine for
   plain shell use, will show garbage for `htop`/`vim`/colored output.
   The `xterm` Flutter package is the natural next layer if that's wanted.
6. **macOS WireGuard routing is incomplete** — only the tunnel interface's
   own address gets configured (`ifconfig`); `AllowedIPs` beyond that
   aren't routed. Fine for archangeld's typical narrow AllowedIPs, not for
   a full-tunnel `0.0.0.0/0` config. See `WireGuardMacOS.swift`'s
   `bringUpInterface`.
7. **`test_utils.dart`'s shared test harness is missing a `FilesService`
   provider** - the cause of `all_sections_test.dart`'s 4 pre-existing
   failures (a `ProviderNotFoundException` when the Files section
   renders in that test's `AppShell`). Low priority (nothing user-facing
   is actually broken - confirmed by running the real app), but worth
   fixing so the suite goes fully green.

## Security hardening history (from `/code-review` passes)

- A real remote-command-injection bug in
  `VpsSetupService._writeConfigIfAbsent` (a free-text "Advanced" field
  was spliced into a quoted shell heredoc - fixed by writing
  `config.yaml` via SFTP instead, same as the setup scripts already
  were, plus input validation in the wizard UI) - regression-tested in
  `test/vps_setup_service_test.dart`.
- SSH host-key verification (was: accept any key silently; now:
  trust-on-first-use with a confirmation dialog, and a stored-fingerprint
  mismatch is never auto-accepted - `lib/services/known_hosts.dart`,
  `lib/services/ssh_transport.dart`'s `resolveHostKeyTrust`,
  `lib/widgets/host_key_dialog.dart` (shared between the setup wizard
  and the backend-update dialog), tested in `test/ssh_transport_test.dart`).
- An OS-level biometric/PIN re-auth gate (`local_auth`,
  `lib/services/local_auth_service.dart`) before reading back a
  "remembered" SSH private key (`lib/services/ssh_credentials.dart`, also
  shared between the wizard and the update dialog) on Android/macOS/
  Windows (no official Linux backend, degrades to no gate there rather
  than locking anyone out - required changing Android's `MainActivity`
  from `FlutterActivity` to `FlutterFragmentActivity`, unverified on a
  real Android device).
- `WireGuardController.bootstrap()` now sets `isBootstrapped` in a
  `finally` block so no exception path can strand `_RootRouter` on its
  loading spinner forever. The wizard's `_enterArchangel()` now catches
  pairing failures instead of leaving a dead "Enter Archangel" button
  with no feedback.
- The Files tab's root jailing itself was a real, critical finding
  (`CleanPath` alone never confined anything - see
  `app/backend/README.md`'s file-browser section) and symlink escapes
  weren't checked - both fixed backend-side, with regression tests in
  `app/backend/internal/files/files_test.go`.

## File map (where things live)

```
lib/
  main.dart                     — app entry, provider wiring
  theme/                        — design tokens ported from the mockup's CSS
  data/
    app_state.dart              — section/accent-color app state
    mock_data.dart               — fake data still used by Containers/DevOps/Overview
  services/
    tunnel_config.dart           — wg-quick config parse/render
    wireguard_controller.dart    — WireGuard state machine, routes to per-platform backend
    macos_wireguard_channel.dart — Dart side of the macOS MethodChannel
    archangeld_connection.dart   — backend host/token pairing + storage + /health version
    terminal_session.dart        — the real PTY-over-WebSocket client
    monitoring_service.dart      — real system metrics/process list, mock fallback
    files_service.dart           — real jailed file browser, mock fallback
    app_version.dart             — the one version (dart-define APP_VERSION/APP_BUILD, fallback = pubspec)
    update_check_service.dart    — fetches GitHub's latest release manifest
    ssh_transport.dart           — dartssh2 wrapper + host-key TOFU
    ssh_credentials.dart         — shared "remember this key" storage
    known_hosts.dart             — TOFU fingerprint store
    local_auth_service.dart      — biometric/PIN re-auth gate
    vps_setup_service.dart       — SSH orchestration: first-time setup + backend update + uninstall
    pairing_bundle.dart          — parses archangeld pair's bundle format
  widgets/                       — shell chrome (top bar, sidebar, command palette),
                                    host_key_dialog.dart, backend_update_dialog.dart,
                                    uninstall_dialog.dart
  screens/                       — the 7 sections + screens/setup/ (the wizard)

macos/Runner/
  WireGuardMacOS.swift          — the unverified native WireGuard backend
  Resources/wireguard-go/       — cross-compiled real wireguard-go binaries
  DebugProfile.entitlements, Release.entitlements — App Sandbox OFF (required)

windows/runner/
  runner.exe.manifest           — requests admin elevation (needed for the tunnel service)

(repo root) scripts/bump_version.sh — bumps pubspec.yaml version + app_version.dart fallback

.github/workflows/release.yml    — tag-triggered build+release pipeline (backend + frontend)

WIREGUARD.md                     — detailed per-platform WireGuard status (read this)
```

## How to pick this up

Read `WIREGUARD.md` in full, then start at gap #1 or #2 above depending on
what you have available (a Mac gets you further than CI access alone).
Everything in this repo is on `main` — there's no feature branch to find.
