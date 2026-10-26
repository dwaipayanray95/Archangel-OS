# Contributing to Archangel

Thanks for helping! This guide gets you from a fresh clone to a pull request.

The project is licensed under [TALv1](LICENSE) (source-available, not OSI open source). Please read it before contributing.

Security problems: please don't open a public issue. See [SECURITY.md](SECURITY.md).

## What is where

| Folder | What |
|---|---|
| `app/backend/` | `archangeld`, the Go server program. See [its README](app/backend/README.md). |
| `app/frontend/` | The Flutter app. See [its README](app/frontend/README.md). |
| `infra/scripts/` | The server setup scripts. This is the **single source of truth**. |
| `app/frontend/assets/setup_scripts/` | Copies of those scripts bundled into the app. Don't edit by hand. |
| `docs/` | User docs. `docs/dev/` holds plans for contributors. |
| `VERSION` | Version numbers (`ARCHANGEL`, `FRONTEND`, `BACKEND`). |

## Dev setup

You need:

| Tool | Version |
|---|---|
| Go | 1.24 (`go.mod` says 1.24.7) |
| Flutter | 3.29.3 (stable). This is what CI uses. |
| `shellcheck` | optional, for script changes |

Then:

```bash
git clone https://github.com/dwaipayanray95/Archangel-OS.git
cd Archangel-OS

# backend
cd app/backend
cp config.example.yaml config.yaml
go run ./cmd/archangeld gen-token     # prints a token and the token_hash line for config.yaml
make run

# frontend (in another terminal)
cd app/frontend
flutter pub get
flutter run -d macos                  # or windows / android
```

For platform details (macOS tunnel helper, Windows admin rights) see [`app/frontend/WIREGUARD.md`](app/frontend/WIREGUARD.md).

## Running tests

```bash
# backend
cd app/backend
go vet ./...
go test ./...
gofmt -l .          # must print nothing

# frontend
cd app/frontend
flutter analyze --no-fatal-infos
flutter test
```

## What CI checks

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push and pull request:

| Job | Checks |
|---|---|
| `backend` | `go vet ./...`, `go test ./...`, `gofmt -l .` is empty |
| `scripts` | Bundled setup assets match `infra/scripts` (`scripts/sync_setup_assets.sh --check`), plus `shellcheck` (warnings only, does not fail the build) |
| `frontend` | `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test` (Flutter 3.29.3) |

## Setup scripts: one source

The setup scripts live in `infra/scripts/`. The app bundles copies, because Flutter can't bundle files from outside its own folder.

After you change any of `baseline_setup.sh`, `wireguard_setup.sh`, `allow_port_before_reject.sh`, `ensure_boot_fw_fixup.sh`, `uninstall.sh` or `archangel.service`, run:

```bash
scripts/sync_setup_assets.sh          # copy to the app
scripts/sync_setup_assets.sh --check  # what CI runs; exits 1 if they differ
```

Commit both the original and the copy.

## Forks

The app checks GitHub Releases, and the setup wizard downloads the server program from them. By default they come from `dwaipayanray95/Archangel-OS`. If you publish your own builds from a fork, point the app at your fork when you build:

```bash
flutter build macos --dart-define=ARCHANGEL_REPO=you/your-fork
```

(Same for `windows` or `apk`.) The setting is read in [`build_config.dart`](app/frontend/lib/services/build_config.dart). Provider-guide links in the app also use it.

## Releases

Versions live in the root [`VERSION`](VERSION) file:

```
BACKEND 0.4.0
FRONTEND 0.5.0
ARCHANGEL 0.6.0
```

- `BACKEND` is baked into `archangeld` at build time. `FRONTEND` is synced into the app by `app/frontend/scripts/sync_version.sh`. `ARCHANGEL` is the release label.
- Bump the lines you changed in a pull request.
- The release workflow ([`release.yml`](.github/workflows/release.yml)) is chosen by the tag:

| Tag | Builds |
|---|---|
| `vX.Y.Z-b` | backend only (`archangeld-amd64`, `archangeld-arm64`, `SHA256SUMS`) |
| `vX.Y.Z-f` | app only (macOS `.dmg`, Windows installer, Android `.apk`) |
| `vX.Y.Z` | both |

Two ways to start one:

1. Push a tag: `git tag v0.6.0 && git push origin v0.6.0`
2. In GitHub, go to **Actions → Release Archangel → Run workflow**, and pick `both`, `backend` or `frontend`. The tag is made from the `ARCHANGEL` line of `VERSION` (plus `-b` or `-f`). It fails if that tag already exists, so bump `ARCHANGEL` first.

Each run also publishes `version-manifest.json`, which the app reads to show "update available".

## Code style

- **Go:** `gofmt`. Standard library first. Keep handlers small, each feature in its own package under `internal/`. Anything that needs root goes through `internal/adminmode`.
- **Dart:** follow `analysis_options.yaml`. New UI goes in `lib/ui/` and uses the design system there (`context.ax` colors, spacing and text styles, `Ax*` components). Don't hard-code colors in screens.
- **Words in the app:** write for a beginner. Say "Apps", not "containers"; "Secure connection", not "tunnel", where you can. Explain unavoidable terms with a `HelpTip`.
- **Danger:** anything destructive needs a confirm dialog that says what will happen.
- **Docs:** short sentences, plain words, numbered steps. Update docs when behavior changes.
- **Tests:** add or update tests with your change.

The UI plan and rules are in [`docs/dev/phase2-ui-plan.md`](docs/dev/phase2-ui-plan.md).

## Pull requests

1. Make a branch.
2. Keep the change focused. Explain what and why.
3. Run the checks above.
4. Open the pull request.
