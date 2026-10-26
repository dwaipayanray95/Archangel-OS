#!/usr/bin/env bash
# Bump the one Archangel OS version.
#
#   scripts/bump_version.sh <major|minor|patch|build>
#
# Reads `version: X.Y.Z+N` from app/frontend/pubspec.yaml, bumps the chosen
# part (lower parts reset to 0), ALWAYS adds 1 to the build number N, and
# writes the result back to the pubspec and to the fallback constants in
# app/frontend/lib/services/app_version.dart (what a plain `flutter run`
# shows). `build` leaves X.Y.Z alone and only adds 1 to N.
#
# Set ARCHANGEL_ROOT to run against another checkout (used for testing).
set -euo pipefail

ROOT="${ARCHANGEL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PUBSPEC="$ROOT/app/frontend/pubspec.yaml"
APP_VERSION_DART="$ROOT/app/frontend/lib/services/app_version.dart"

usage() {
  echo "Usage: scripts/bump_version.sh <major|minor|patch|build>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
part="$1"

line=$(grep -E '^version: ' "$PUBSPEC" || true)
if [[ ! "$line" =~ ^version:\ ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
  echo "ERROR: expected 'version: X.Y.Z+N' in $PUBSPEC, found: ${line:-<nothing>}" >&2
  exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
build="${BASH_REMATCH[4]}"
old="$major.$minor.$patch+$build"

case "$part" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  build) ;;
  *) usage ;;
esac
build=$((build + 1))
semver="$major.$minor.$patch"
new="$semver+$build"

sed -i.bak -E "s/^version: .*/version: $new/" "$PUBSPEC"
rm -f "$PUBSPEC.bak"
if [[ -f "$APP_VERSION_DART" ]]; then
  sed -i.bak -E \
    -e "s/(static const String fallbackVersion = ')[^']*(';)/\1$semver\2/" \
    -e "s/(static const int fallbackBuild = )[0-9]+(;)/\1$build\2/" \
    "$APP_VERSION_DART"
  rm -f "$APP_VERSION_DART.bak"
fi

echo "Version: $old -> $new"
echo
echo "Next steps:"
echo "  1. git commit -am \"Release v$semver\" && git push"
echo "  2. GitHub -> Actions -> Release Archangel -> Run workflow"
echo "     (it tags v$semver and builds the server program and all apps)"
