#!/bin/bash
# Baseline hardening/setup for a fresh Project Archangel instance: system
# update, swap, tmux, and an SSH-only ufw firewall. Matches infra/README.md
# section 9's manual checklist exactly - this is that checklist, scripted.
#
# Safe to re-run: every step checks whether it's already done before acting,
# so running this again on an already-set-up box is a harmless no-op (unlike
# wireguard_setup.sh, which refuses to re-run without --force since
# WireGuard identity/pairing can't be silently regenerated safely).
set -euo pipefail

SWAP_FILE="/swapfile"
SWAP_SIZE_GB=2

echo "==> Updating system packages"
sudo apt update -qq
sudo apt upgrade -y -qq

echo "==> Swap"
if sudo swapon --show | grep -q "$SWAP_FILE"; then
  echo "    Swap already active at $SWAP_FILE - skipping."
else
  sudo fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE"
  sudo chmod 600 "$SWAP_FILE"
  sudo mkswap "$SWAP_FILE" > /dev/null
  sudo swapon "$SWAP_FILE"
  if ! grep -q "^$SWAP_FILE " /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
  fi
  echo "    Added ${SWAP_SIZE_GB}G swap at $SWAP_FILE."
fi

echo "==> dbus-user-session (systemd user manager for terminals)"
if dpkg -s dbus-user-session > /dev/null 2>&1; then
  echo "    dbus-user-session already installed - skipping."
else
  sudo apt install -y -qq dbus-user-session
fi

echo "==> tmux"
if command -v tmux > /dev/null; then
  echo "    tmux already installed - skipping."
else
  sudo apt install -y -qq tmux
fi

echo "==> ufw (SSH + HTTP/HTTPS baseline)"
if ! command -v ufw > /dev/null; then
  sudo apt install -y -qq ufw
fi
sudo ufw allow OpenSSH > /dev/null || sudo ufw allow 22/tcp > /dev/null
sudo ufw allow 80/tcp > /dev/null
sudo ufw allow 443/tcp > /dev/null
if sudo ufw status | grep -q "Status: active"; then
  echo "    ufw already active."
else
  sudo ufw --force enable > /dev/null
fi

echo "==> Docker Engine"
if command -v docker > /dev/null; then
  echo "    Docker Engine already installed - skipping."
else
  echo "    Installing Docker Engine via official script..."
  curl -fsSL https://get.docker.com | sh
  sudo systemctl enable --now docker
fi
if id archangel > /dev/null 2>&1; then
  sudo usermod -aG docker archangel || true
fi

# Archangel publishes container ports on the WireGuard address by default
# (private to your devices). Docker can only bind that address once wg0 is
# up, so make Docker wait for the tunnel at boot - otherwise those
# containers fail to start after a reboot.
echo "==> Ordering Docker after WireGuard"
sudo mkdir -p /etc/systemd/system/docker.service.d
printf '[Unit]\nAfter=wg-quick@wg0.service\nWants=wg-quick@wg0.service\n' | sudo tee /etc/systemd/system/docker.service.d/archangel-wg.conf > /dev/null
sudo systemctl daemon-reload

echo "==> Caddy Reverse Proxy"
if command -v caddy > /dev/null; then
  echo "    Caddy already installed - skipping."
else
  echo "    Installing Caddy from official deb repo..."
  sudo apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
  sudo apt update -qq
  sudo apt install -y -qq caddy
  sudo systemctl enable --now caddy
  echo "    Caddy reverse proxy installed and service enabled."
fi
if id archangel > /dev/null 2>&1 && [ -d /etc/caddy ]; then
  sudo chown -R root:archangel /etc/caddy
  sudo chmod 775 /etc/caddy
fi

echo "==> Done. Current state:"
free -h
sudo ufw status
