# Archangel (Flutter app)

The Flutter app for macOS, Windows and Android. It is the GUI for [`archangeld`](../backend/README.md), the Go server program on your VPS. It is also the VPN client: it manages the WireGuard tunnel itself. And it sets the server up in the first place.

New to Archangel? Start with the [user docs](../../docs/getting-started.md). This page is for people working on the app.

Related notes: [`WIREGUARD.md`](WIREGUARD.md) (per-platform tunnel details) and [`WORKING.md`](WORKING.md) (older working notes; parts predate the Phase 2 UI rewrite, so trust the code where they differ).

## What the app does

- **Setup flow** (`lib/screens/setup/`, `lib/ui/screens/setup/`): a welcome screen ("Do you have a server?"): set it up for me, I have a pairing code, or "not yet" (provider guides in `docs/guides/`). The wizard is one question per screen, then a summary, then live progress. On failure it explains what went wrong in plain words (`setup_hints.dart`) and lets you retry.
- **Server setup over SSH** (`lib/services/vps_setup_service.dart`): uploads the bundled scripts, runs them, downloads and checksum-verifies `archangeld`, installs the service, and pairs this device. Also does updates (with rollback), "sync server permissions", turning Admin mode on, and uninstall.
- **Home, Apps, Files, Terminal, Activity, Services, Settings**: all real data from the server, no mock data.
- **Multiple servers**: a server registry with a switcher.
- **Pair another device**: pairing dialog (paste a code, or scan a QR on Android).

## Code layout (`lib/`)

| Folder | What is in it |
|---|---|
| `main.dart` | App entry. Sets up providers and chooses between the setup flow and the shell. |
| `ui/` | The design system and the new UI. See below. |
| `screens/` | Screen widgets: `overview_screen` (Home), `containers_screen` (Apps), `files_screen`, `terminal_screen`, `monitoring_screen` (Activity), `devops_screen` (Services), `settings_screen`, plus `setup/`. |
| `services/` | Everything that talks to the outside world: SSH, WireGuard, API clients (`*_service.dart`), pairing, credential encryption, update checks. |
| `models/` | Data classes. |
| `data/app_state.dart` | Current section, appearance (theme mode, accent). |
| `theme/`, `widgets/` | Older theme tokens and dialogs. `widgets/` still holds shared dialogs (pairing, update, sync, uninstall, SSH key). |

### The design system and shell (`lib/ui/`)

- `ui/theme.dart`, `ui/ui.dart`: `ArchangelTheme` is a `ThemeExtension` with light and dark palettes. Access it as `context.ax` (colors, spacing, radii, text styles). Don't hard-code colors in screens.
- `ui/components/`: shared building blocks. `AxButton`, `AxCard`, `AxListTile`, `AxPage`, `StatusBadge`, `ConfirmDialog`, `HelpTip`, `SshCredentialsForm`, and loading/empty/error views (`state_views.dart`).
- `ui/shell/`: the root shell, `ArchangelShell`. A bottom bar on phones (under 720 px wide; Activity, Services and Settings are under "More") and a navigation rail on larger screens (labels from 1100 px). It includes the server switcher, a status strip, and the destinations list (`destinations.dart`). Each destination is built when first visited and kept alive, but **only the visible one polls the server**.
- `ui/screens/<name>/`: logic and widgets per screen (`home_logic.dart`, `app_specs.dart`, `services_logic.dart`, and so on). Pure logic is kept separate so it can be unit tested.

`screens/settings_screen.dart` and some dialogs in `widgets/` still use the older `AxColors` constants. They are being moved to the design system. The plan and rules are in [`docs/dev/phase2-ui-plan.md`](../../docs/dev/phase2-ui-plan.md).

### Server registry (`lib/services/server_registry.dart`)

`ServerRegistry` stores a list of `ServerProfile`s (name, `host:port` on the tunnel, token, WireGuard config, SSH host and user, app port, WireGuard port) and which one is active. An older single pairing is migrated to the first profile on launch.

Switching servers disconnects the current tunnel, brings up the other server's tunnel, re-points `ArchangeldConnection`, and resets per-server state. Only one tunnel runs at a time (mobile systems allow one VPN). Update, uninstall and sync always use the active profile's ports and SSH host.

## Run it

You need Flutter 3.29.3 (what CI uses).

```bash
cd app/frontend
flutter pub get
flutter run -d macos        # or: windows, an Android device/emulator. See `flutter devices`
```

Notes: the Windows app asks for admin rights (needed to create the tunnel service). On Linux, the tunnel shells out to `wg-quick` via sudo; Linux is a dev target only and isn't released. See [`WIREGUARD.md`](WIREGUARD.md).

## Check it

```bash
flutter analyze --no-fatal-infos
flutter test
dart format .
```

CI runs the first two. Tests are in `test/` (services, screens at phone and desktop sizes, the shell, the setup wizard).

## Build

```bash
flutter build macos
flutter build windows
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Forks that publish their own releases point the app at their repo:

```bash
flutter build macos --dart-define=ARCHANGEL_REPO=you/your-fork
```

This sets the repo used for update checks, backend downloads and provider-guide links (`lib/services/build_config.dart`).

## Setup scripts

The scripts the wizard uploads are copies in `assets/setup_scripts/`. The originals are in [`infra/scripts/`](../../infra/scripts). After changing one, run `scripts/sync_setup_assets.sh` from the repo root (CI checks with `--check`).

## Versions and releases

`scripts/sync_version.sh` copies the `FRONTEND` line of the root [`VERSION`](../../VERSION) into `pubspec.yaml` and `lib/services/app_version.dart`. Run it after bumping `VERSION`; CI runs it before every release build. Release builds (macOS `.dmg`, Windows installer, Android arm64 `.apk`) come from the tag-driven pipeline. See [CONTRIBUTING.md](../../CONTRIBUTING.md#releases).
