#!/usr/bin/env bash
# Copies the canonical server scripts in infra/scripts/ into the Flutter
# app's bundled assets. With --check, exits 1 and prints a diff if they differ.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/infra/scripts"
DST="$ROOT/app/frontend/assets/setup_scripts"
FILES=(baseline_setup.sh wireguard_setup.sh allow_port_before_reject.sh ensure_boot_fw_fixup.sh uninstall.sh archangel.service)

if [ "${1:-}" = "--check" ]; then
  rc=0
  for f in "${FILES[@]}"; do
    if ! diff -u "$SRC/$f" "$DST/$f"; then rc=1; fi
  done
  if [ "$rc" -ne 0 ]; then
    echo "Setup assets are out of sync. Run scripts/sync_setup_assets.sh" >&2
  fi
  exit "$rc"
fi

for f in "${FILES[@]}"; do cp "$SRC/$f" "$DST/$f"; done
echo "Synced ${#FILES[@]} files to app/frontend/assets/setup_scripts/"
