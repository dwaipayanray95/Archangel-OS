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
| `scripts/` | Repo helper scripts, including `bump_version.sh` (see Releases). |

## Dev setup

You need:

| Tool | Version |
|---|---|
| Go | 1.24 (`go.mod` says 1.24.7) |
| Flutter | 3.47.8 (stable). This is what CI uses. |
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
| `frontend` | `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test` (Flutter 3.47.8) |

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

There is **one version** for the whole product (the app and the server program). It lives in one place: `version:` in [`app/frontend/pubspec.yaml`](app/frontend/pubspec.yaml), written `MAJOR.MINOR.PATCH+BUILD`, for example `0.8.0+2`.

- `MAJOR.MINOR.PATCH` is the release name and the tag (`v0.8.0`). It is baked into `archangeld` at build time (the Makefile reads it from the pubspec), and shown in the app as "Archangel OS 0.8.0 (build 2)".
- `BUILD` goes up by 1 on every release, even when the semver part doesn't change.
- Release builds pass the version to the app with `--dart-define=APP_VERSION=...` and `APP_BUILD=...`. A local `flutter run` has no defines and shows the fallback constants in [`app_version.dart`](app/frontend/lib/services/app_version.dart). `scripts/bump_version.sh` keeps those in step with the pubspec, and a test fails if they drift.

### How to release

1. Run `scripts/bump_version.sh <major|minor|patch|build>` from the repo root. It bumps the chosen part (lower parts reset to 0), always adds 1 to the build number, and prints the old and new version.
2. Commit the change and push it to the branch you release from.
3. In GitHub, go to **Actions → Release Archangel → Run workflow**. The workflow reads the pubspec, fails straight away if the tag `vX.Y.Z` already exists, creates the tag, and builds everything: `archangeld` (amd64 and arm64, with `SHA256SUMS`), the macOS `.dmg`, the Windows installer and the Android `.apk`. It also publishes `version-manifest.json`.

Pushing the tag yourself (`git tag v0.8.0 && git push origin v0.8.0`) works too, if the tag matches the pubspec version at that commit.

The app reads `version-manifest.json` from the latest release to show "update available". It looks like `{"version": "0.8.0", "build": 2, "tag": "v0.8.0"}`, plus a few legacy keys (`archangel`, `frontend`, `backend`, `frontend_tag`, `backend_tag`, all set from the same version and tag) so apps installed before the single version still see the update. Don't remove them until those apps are gone.

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
