#!/bin/bash
# Master setup entrypoint for a fresh Archangel OS instance (Ampere A1
# or AMD Micro). Run this once on a brand-new box to get it from "just
# launched" to "fully set up" in one command:
#
#   git clone https://github.com/dwaipayanray95/Archangel-OS.git
#   cd Archangel-OS
#   ./infra/scripts/install-archangel.sh
#
# This is a thin orchestrator, not a monolith - it calls the individual
# setup scripts in infra/scripts/ in order. Each of those stays independently
# runnable and has its own re-run semantics (baseline_setup.sh is always
# safe to re-run; wireguard_setup.sh refuses to re-run without --force,
# since re-running it would silently invalidate every already-paired
# device). Keeping them separate means any one piece can be re-run in
# isolation later without repeating everything else - e.g. adding a 4th
# WireGuard peer, or re-deploying just the backend after a code change.
#
# As new milestones land (see the app/backend build plan), this script
# grows a new step each time - it's meant to be the canonical "how do I set
# this box up" answer, kept current as the project grows, not a one-time
# snapshot of what setup looked like on one particular day.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "############################################"
echo "# Archangel OS - full instance setup"
echo "############################################"
echo ""

echo "==> [1/2] Baseline (update, swap, tmux, ufw SSH-only)"
"$SCRIPT_DIR/baseline_setup.sh"
echo ""

echo "==> [2/2] WireGuard (server + phone/mac/windows peers)"
if [[ -f /etc/wireguard/wg0.conf ]]; then
  echo "    /etc/wireguard/wg0.conf already exists - skipping to avoid"
  echo "    invalidating already-paired devices. To force regeneration,"
  echo "    run: $SCRIPT_DIR/wireguard_setup.sh --force"
else
  "$SCRIPT_DIR/wireguard_setup.sh"
fi
echo ""

echo "############################################"
echo "# Baseline + WireGuard setup complete on this box."
echo "#"
echo "# Remaining manual step: open 51820/udp in the OCI Console's"
echo "# Security List (VCN-level firewall) - ufw alone isn't enough,"
echo "# see infra/README.md section 10."
echo "#"
echo "# This script only covers what runs ON the server. The backend"
echo "# (app/backend) deploys from a DIFFERENT machine - your own laptop,"
echo "# not this box - since it builds the Go binary locally and pushes"
echo "# it over. It can't be folded into this script; run it separately"
echo "# from your own machine once this finishes:"
echo "#   cd app/backend && ./deploy.sh"
echo "############################################"
