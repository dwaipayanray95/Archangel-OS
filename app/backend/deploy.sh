#!/bin/bash
# Deploys archangeld to a server. Run this from YOUR OWN machine (Mac,
# etc.) - not on the server itself, since it needs to build the binary
# locally and then push it over. This is the entire manual deployment
# walkthrough (create user/dirs, install the binary, generate a token,
# write config, install the systemd service, verify) scripted end to end,
# the same way infra/scripts/wireguard_setup.sh scripted WireGuard setup.
#
# Safe to re-run: every step checks the server's actual current state
# before acting. Re-running does NOT regenerate the auth token (that would
# silently break an already-paired app) - it only rotates the deployed
# binary and restarts the service, unless /etc/archangel/config.yaml is
# missing entirely (first-time deploy).
#
# Usage:
#   ./deploy.sh
#   SERVER_HOST=1.2.3.4 SERVER_USER=ubuntu ./deploy.sh   (override defaults)
set -euo pipefail

# ===== CONFIG - override any of these as env vars if your setup differs =====
SERVER_HOST="${SERVER_HOST:-<YOUR_SERVER_IP>}"
SERVER_USER="${SERVER_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-$HOME/Downloads/project-archangel.key}"
# Must be the server's WireGuard interface IP, never 0.0.0.0 or its public
# IP - same rule config.go itself enforces at startup.
WG_BIND_ADDR="${WG_BIND_ADDR:-10.10.0.1}"
PORT="${PORT:-8443}"
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ssh_cmd() { ssh -i "$SSH_KEY" -o BatchMode=yes "${SERVER_USER}@${SERVER_HOST}" "$@"; }
scp_cmd() { scp -i "$SSH_KEY" "$@"; }

echo "################################################################"
echo "# Project Archangel backend - deploy"
echo "# Target: ${SERVER_USER}@${SERVER_HOST}  (bind ${WG_BIND_ADDR}:${PORT})"
echo "################################################################"
echo ""

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key not found at $SSH_KEY"
  echo "Set SSH_KEY=/path/to/your/key if it's somewhere else, e.g.:"
  echo "  SSH_KEY=~/Downloads/project-archangel.key ./deploy.sh"
  exit 1
fi

echo "==> [1/7] Building archangeld for linux/amd64"
if ! command -v go > /dev/null; then
  echo "ERROR: Go isn't installed on this machine."
  echo "Install it first - on a Mac: brew install go"
  echo "(or see https://go.dev/dl/ for other platforms), then re-run this script."
  exit 1
fi
( cd "$SCRIPT_DIR" && make build-linux-amd64 )
echo "    Built: $SCRIPT_DIR/bin/archangeld-amd64"
echo ""

echo "==> [2/7] Checking the connection to $SERVER_HOST"
if ! ssh_cmd "echo ok" > /dev/null 2>&1; then
  echo "ERROR: could not SSH to ${SERVER_USER}@${SERVER_HOST} using $SSH_KEY."
  echo "Check the server is up, the IP is current, and the key path/permissions"
  echo "are correct (chmod 600 on the key file if SSH complains about that)."
  exit 1
fi
echo "    Connected OK."
echo ""

echo "==> [3/7] Ensuring the server user + directories exist"
ssh_cmd bash <<'REMOTE'
set -e
if id archangel > /dev/null 2>&1; then
  echo "    archangel system user already exists."
  # Ensure home directory exists if user was created earlier without one
  sudo mkdir -p /home/archangel
  sudo chown archangel:archangel /home/archangel
  sudo usermod -d /home/archangel -s /bin/bash archangel || true
else
  sudo useradd --system --create-home --home-dir /home/archangel --shell /bin/bash archangel
  echo "    Created archangel system user with home /home/archangel."
fi
sudo mkdir -p /opt/archangel/deploy /home/archangel/deploy /srv/deploy /etc/archangel
sudo chown -R archangel:archangel /opt/archangel/deploy /home/archangel/deploy /srv/deploy
sudo chmod 775 /opt/archangel/deploy /home/archangel/deploy /srv/deploy
sudo chown root:archangel /etc/archangel
sudo chmod 750 /etc/archangel

# Hybrid Cockpit: grant passwordless sudo to archangel user
echo "archangel ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/archangel > /dev/null
sudo chmod 440 /etc/sudoers.d/archangel

# Ensure Docker Engine & Compose are installed and archangel user is in docker group
if ! command -v docker &> /dev/null; then
  echo "    Docker Engine not found - installing official Docker packages..."
  curl -fsSL https://get.docker.com | sh
  sudo systemctl enable --now docker
  echo "    Docker Engine installed and service enabled."
else
  echo "    Docker Engine already installed."
fi
sudo usermod -aG docker archangel || true

# Ensure Caddy reverse proxy is installed and ports 80/443 are allowed
if ! command -v caddy &> /dev/null; then
  echo "    Caddy reverse proxy not found - installing official Caddy packages..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq caddy
  sudo systemctl enable --now caddy
  echo "    Caddy reverse proxy installed and service enabled."
else
  echo "    Caddy reverse proxy already installed."
fi

if [ -d /etc/caddy ]; then
  sudo chown -R root:archangel /etc/caddy
  sudo chmod 775 /etc/caddy
fi

# Allow HTTP and HTTPS in ufw if ufw is active
if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 80/tcp > /dev/null
  sudo ufw allow 443/tcp > /dev/null
fi

echo "    Sudoers configuration, Docker access, Caddy reverse proxy, and directories ready."
REMOTE
echo ""

echo "==> [4/7] Copying and installing the binary"
scp_cmd "$SCRIPT_DIR/bin/archangeld-amd64" "${SERVER_USER}@${SERVER_HOST}:/tmp/archangeld"
ssh_cmd bash <<'REMOTE'
set -e
sudo mv /tmp/archangeld /opt/archangel/archangeld
sudo chmod 755 /opt/archangel/archangeld
sudo chown root:root /opt/archangel/archangeld
echo "    Installed to /opt/archangel/archangeld"
REMOTE
echo ""

echo "==> [5/7] Server config"
if ssh_cmd 'sudo test -f /etc/archangel/config.yaml'; then
  echo "    /etc/archangel/config.yaml already exists - leaving the existing"
  echo "    token in place (regenerating it here would silently break an"
  echo "    already-paired app). Delete it on the server first if you"
  echo "    genuinely want to rotate the token, then re-run this script."
else
  echo "    No config yet - generating a fresh auth token..."
  GEN_OUTPUT=$(ssh_cmd "sudo /opt/archangel/archangeld gen-token")

  TOKEN=$(echo "$GEN_OUTPUT" | grep -A2 "shown once" | tail -1 | tr -d ' ')
  TOKEN_HASH=$(echo "$GEN_OUTPUT" | grep 'token_hash:' | sed -E 's/.*token_hash: "(.*)"/\1/')

  if [[ -z "$TOKEN" || -z "$TOKEN_HASH" ]]; then
    echo "ERROR: could not parse the token/hash out of gen-token's output."
    echo "Nothing was written - raw output was:"
    echo "$GEN_OUTPUT"
    exit 1
  fi
  # Cheap sanity check before trusting these values: re-derive the hash
  # locally and confirm it actually matches what was parsed as the hash,
  # catching a parsing bug (mismatched lines, wrong field) rather than
  # silently writing a token/hash pair that don't correspond to each other.
  RECOMPUTED_HASH=$(printf '%s' "$TOKEN" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || printf '%s' "$TOKEN" | sha256sum | cut -d' ' -f1)
  if [[ "$RECOMPUTED_HASH" != "$TOKEN_HASH" ]]; then
    echo "ERROR: parsed token and token_hash don't correspond to each other"
    echo "(sha256(token) = $RECOMPUTED_HASH, but parsed hash = $TOKEN_HASH)."
    echo "Something is wrong with the output parsing - nothing was written."
    exit 1
  fi

  ssh_cmd "sudo tee /etc/archangel/config.yaml > /dev/null <<CONF
bind_addr: \"$WG_BIND_ADDR\"
port: $PORT
token_hash: \"$TOKEN_HASH\"
files_root: \"/home/archangel\"
CONF
sudo chown root:archangel /etc/archangel/config.yaml
sudo chmod 640 /etc/archangel/config.yaml"

  echo ""
  echo "    ================================================================"
  echo "    NEW API TOKEN - shown once, save it in a password manager NOW:"
  echo ""
  echo "      $TOKEN"
  echo ""
  echo "    You'll need this to pair the Flutter app. The server only ever"
  echo "    stores its hash - this is the only time the plaintext appears."
  echo "    ================================================================"
fi
echo ""

echo "==> [6/7] Installing and (re)starting the systemd service"
scp_cmd "$SCRIPT_DIR/../../infra/scripts/archangel.service" "${SERVER_USER}@${SERVER_HOST}:/tmp/archangel.service"
ssh_cmd bash <<'REMOTE'
set -e
sudo mv /tmp/archangel.service /etc/systemd/system/archangel.service
sudo systemctl daemon-reload
sudo systemctl enable --now archangel
sudo systemctl restart archangel
sleep 1
if sudo systemctl is-active --quiet archangel; then
  echo "    Service active."
else
  echo "ERROR: service failed to start. Check: sudo systemctl status archangel"
  echo "and: sudo journalctl -u archangel -n 50 --no-pager"
  exit 1
fi
REMOTE
echo ""

echo "==> [7/7] Firewall: opening ${PORT}/tcp (WireGuard interface only)"
# ufw's own rule is still worth having as a second, independent layer, but
# on Archangel-Mk1 it alone was NOT sufficient - a pre-existing catch-all
# reject rule in the raw kernel ruleset (unrelated to ufw, sits ahead of
# it) silently ate every connection despite `ufw status` and `ss -tlnp`
# both looking completely correct. See infra/README.md section 10 for the
# full incident writeup. allow_port_before_reject.sh is the actual fix;
# ensure_boot_fw_fixup.sh makes it (and the ufw rule) survive a reboot.
ssh_cmd "sudo ufw allow in on wg0 to any port ${PORT} proto tcp" > /dev/null || true

INFRA_SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../infra/scripts" && pwd)"
scp_cmd "$INFRA_SCRIPTS_DIR/allow_port_before_reject.sh" "$INFRA_SCRIPTS_DIR/ensure_boot_fw_fixup.sh" \
  "${SERVER_USER}@${SERVER_HOST}:/tmp/"
ssh_cmd bash <<REMOTE
set -e
sudo mkdir -p /opt/archangel-infra-scripts
sudo mv /tmp/allow_port_before_reject.sh /tmp/ensure_boot_fw_fixup.sh /opt/archangel-infra-scripts/
sudo chmod 755 /opt/archangel-infra-scripts/*.sh
/opt/archangel-infra-scripts/allow_port_before_reject.sh ${PORT} tcp
/opt/archangel-infra-scripts/ensure_boot_fw_fixup.sh ${PORT} tcp
REMOTE
echo ""

echo "################################################################"
echo "# Deploy complete."
echo "################################################################"
echo ""
echo "Next steps:"
echo "  1. Make sure your WireGuard tunnel to the server is active."
echo "  2. Check the health endpoint over WireGuard:"
echo "       curl http://${WG_BIND_ADDR}:${PORT}/api/v1/health"
echo "     Expected: {\"status\":\"ok\"}"
echo "  3. Confirm it's NOT reachable via the public IP (proves bind_addr"
echo "     is actually doing its job):"
echo "       curl -m 3 http://${SERVER_HOST}:${PORT}/api/v1/health"
echo "     Expected: times out / connection refused."
echo "  4. Test a real terminal session (curl can't drive WebSockets):"
echo "       websocat \"ws://${WG_BIND_ADDR}:${PORT}/ws/terminal?token=<your token>\""
echo "     (brew install websocat if you don't have it yet)"
