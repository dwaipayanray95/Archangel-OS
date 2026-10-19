# Project Archangel — Infra

Personal Oracle Cloud (OCI) Always-Free VPS setup — vibecoding box, dev sandbox, and home for whatever self-hosted experiments come next.

This is the **recovery runbook**. If a server dies, gets deleted, or a fresh account is needed, everything required to rebuild it from scratch lives here.

> Just want to use Archangel? You don't need this page. Start with the
> [user guide](../docs/getting-started.md) and the provider guides in
> [`docs/guides/`](../docs/guides/oracle-cloud.md). This page is the deep
> reference for what the setup scripts do.

**There is now a faster path for the WireGuard + backend half of this**:
the Flutter app's in-app setup wizard runs the exact scripts below over
SSH for you, no manual steps 1 and 3 required - see
[`app/frontend/README.md`](../app/frontend/README.md#what-the-app-does).
This runbook remains the reference for what those scripts actually do,
manual recovery if the wizard isn't available, and everything OCI/account
-side the wizard can't touch (section 8's firewall gotcha in particular).
The reverse also exists in-app now — `infra/scripts/uninstall.sh` tears
WireGuard and archangeld back down, run from Settings' "Danger zone" the
same way; see [`app/backend/README.md#uninstalling`](../app/backend/README.md#uninstalling).

---

## Quickstart: set up a fresh server

Two steps, run from two different places — details, caveats, and everything each one actually does are in sections 1-9 below, but this is the whole thing end to end.

**1. On the new server itself** (SSH in first — see section 4 for the connection command), gets it from "just launched" to "baseline + WireGuard fully configured, firewall gotcha fixed and boot-persisted":
```bash
git clone https://github.com/dwaipayanray95/Project-Archangel.git
cd Project-Archangel
./infra/scripts/install-archangel.sh
```

**2. One manual step this can't automate:** open `51820/udp` in the OCI Console's Security List (VCN-level firewall — `ufw` alone isn't enough, see section 8). `install-archangel.sh` prints this reminder at the end too.

**3. From your own machine** (not the server — this builds the Go binary locally and pushes it over), deploys the backend:
```bash
cd Project-Archangel/app/backend
./deploy.sh
```
Prints a fresh API token once at the end — save it in a password manager immediately, you'll need it to pair the Flutter app.

Both `install-archangel.sh` and `deploy.sh` are safe to re-run — they check the server's actual state before doing anything and never silently regenerate a WireGuard peer or auth token that's already paired with a device.

---

## 1. Account & Region

- **Cloud provider:** Oracle Cloud Infrastructure (OCI), Always Free tier
- **Region:** `ap-mumbai-1` (Mumbai) — only one availability domain (`AD-1`), so no AD-switching workaround for capacity issues
- **Free tier limits on this account:** capped at **2 OCPU / 12 GB** total for Ampere A1 (Arm) shapes — lower than the commonly-advertised 4 OCPU/24GB, likely account/region dependent
- Also available separately: up to 2x AMD-based "Micro" instances (1/8 OCPU, 1GB RAM each) — one is in use, see section 3

## 2. Ampere A1 Instance Configuration

| Setting | Value |
|---|---|
| Shape | `VM.Standard.A1.Flex` (Ampere ARM, Always Free eligible) |
| OCPUs | 1 |
| Memory | 6 GB |
| OS Image | Canonical Ubuntu 24.04 (plain, not Minimal), ARM build |
| Image OCID used | `ocid1.image.oc1.ap-mumbai-1.<REDACTED>` (2026.07.17-0 — **check for newer image OCIDs when rebuilding**, these expire/rotate) |
| VCN/Subnet | `vcn-20260506-1516` / `subnet-20260506-1516` (auto-selected defaults) |
| Public IPv4 | Assigned automatically |
| IPv6 | Off |
| Shielding / Confidential Computing | Off (not needed for this use case) |
| Boot volume | Default ~46.6GB, in-transit encryption on, Oracle-managed keys |

**Why 1 OCPU/6GB instead of the full 2/12?** Smaller requests succeed more often when scavenging for scarce free-tier Ampere capacity — this is a widely recommended trick, not just our guess. Once the box is up, it can be resized later if more capacity frees up.

**Status:** not yet allocated — no automated retry in place (see section 6); provision manually via the Console when capacity is available.

## 3. AMD Micro Instance Configuration (`Archangel-Mk1`)

Provisioned directly via the OCI Console — no capacity scarcity issue for this shape, so no retry script needed.

| Setting | Value |
|---|---|
| Instance name | `Archangel-Mk1` |
| Shape | `VM.Standard.E2.1.Micro` (AMD, Always Free eligible) |
| OCPUs | 1/8 |
| Memory | 1 GB |
| OS Image | Canonical Ubuntu 24.04 (plain, not Minimal), x86_64 build — exact image OCID not captured at launch time (selected via Console default); **grab the current x86_64 Ubuntu 24.04 image OCID from the Console if rebuilding** |
| Public IPv4 | `<YOUR_SERVER_IP>` |
| Created | 2026-09-01 |

**Status:** running, baseline setup complete (see section 7), WireGuard configured with 3 peers (see section 8) — OCI Security List rule for `51820/udp` still needs adding before any device can actually connect.

## 4. SSH Access

- Keypair was generated via the OCI Console during instance creation ("Generate a key pair for me")
- **Private key** lives at: `~/Downloads/project-archangel.key` on your Mac — **never commit this to git, never copy it onto the VPS itself**
- **Public key** lives at: `~/Downloads/project-archangel-public.key.pub` — safe to share/commit, this is what's actually installed in the VPS's `authorized_keys`
- **Same keypair is reused across both instances** (Ampere and AMD Micro) — simpler to manage, at the cost of both boxes sharing blast radius if the private key is ever compromised. Acceptable tradeoff for a personal sandbox setup.
- If the private key is ever lost: don't try to recover it — generate a fresh keypair and update `authorized_keys` on next rebuild. A password manager (Bitwarden/1Password secure file storage) is the recommended backup location for the private key — **not** GitHub, not the VPS itself.
- **Local file permissions matter:** SSH refuses to use a private key file that's readable by other users. If you see `Permissions 0644 for '...' are too open` / `bad permissions`, fix with:
  ```bash
  chmod 600 ~/Downloads/project-archangel.key
  ```

Connect with:
```bash
ssh -i ~/Downloads/project-archangel.key ubuntu@<VPS_PUBLIC_IP>
```
First connection to a given IP will prompt to confirm the host key fingerprint — type `yes`. This is expected and only happens once per IP (seeing it again later on the same IP is a signal the server was rebuilt).

## 5. OCI CLI Setup (on the machine used to provision/manage the VPS)

1. Install OCI CLI (official install script) — installed to `~/bin/oci` on Mac, added to PATH via `~/.zshrc`
2. Run `oci setup config`:
   - Region: `ap-mumbai-1`
   - Generates a separate RSA **API signing keypair** (different from the SSH keypair above) at `~/.oci/oci_api_key.pem` (private) and `~/.oci/oci_api_key_public.pem` (public)
   - **This key *is* passphrase-encrypted** (despite earlier notes here once saying otherwise). The passphrase itself lives wherever the Mac's `oci setup config` prompt answer went (password manager recommended, same as the SSH key)
3. Upload the API public key in OCI Console → **My Profile → API Keys**
4. Verify with: `oci iam region list`

**Key OCIDs (this account/tenancy):**
- Tenancy/Compartment OCID: `ocid1.tenancy.oc1..<REDACTED>`
- Availability Domain: `EBDD:AP-MUMBAI-1-AD-1`
- Subnet OCID: `ocid1.subnet.oc1.ap-mumbai-1.<REDACTED>`

> ⚠️ OCIDs are account-specific. If rebuilding under a **different** OCI account/tenancy, all of the above OCIDs must be re-fetched — they will not match.

## 6. The Capacity Problem (Ampere A1 only)

Oracle's free-tier Ampere A1 capacity is notoriously scarce, especially in Indian regions. Instance creation via the Console repeatedly failed with:
```
Out of capacity for shape VM.Standard.A1.Flex in availability domain AD-1
```
This is a widely-documented issue — community reports mention it can take anywhere from days to 1–3 months of continuous retrying to catch a free slot, sometimes 100,000+ attempts. **The AMD Micro shape has no such scarcity problem** — that instance was created directly via the Console with no retrying needed.

No automated retry is set up for this repo. If chasing this capacity again, either retry manually via the Console, or script your own loop around `oci compute instance launch` with your own (never-committed) tenancy/subnet/image OCIDs.

## 7. Baseline Post-Launch Setup (repeat for every new instance)

Applied to `Archangel-Mk1` (AMD Micro) on 2026-09-01. **Run this same sequence on the Ampere A1 instance once it's allocated.**

**Scripted**: [`infra/scripts/baseline_setup.sh`](scripts/baseline_setup.sh) — safe to re-run any time, every step checks whether it's already done first. It now does more than the manual steps below: besides the system update, 2 GB swap, `tmux` and `ufw` (SSH plus 80/tcp and 443/tcp), it also installs:
- `dbus-user-session` (so `archangeld` can start persistent terminal sessions under the `archangel` user's systemd user manager)
- **Docker Engine** (official `get.docker.com` script), adds the `archangel` user to the `docker` group if it exists, and orders `docker.service` after `wg-quick@wg0` so containers published on the tunnel address can bind at boot
- **Caddy** (official apt repo), with `/etc/caddy` made group-writable by `archangel` so the Services screen can manage web addresses
```bash
git clone https://github.com/dwaipayanray95/Project-Archangel.git && cd Project-Archangel
./infra/scripts/baseline_setup.sh
```

Manual steps (what the script above actually does, kept here as reference/fallback):

1. **Retrieve the public IP** — OCI Console → instance → Details tab → Public IP Address
2. **First SSH connection**, confirm access (accept the host key fingerprint prompt — see section 4)
3. **Update the base system:**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```
4. **Add swap** — critical on low-RAM shapes (the AMD Micro's 1GB especially), prevents an OOM crash from a memory spike:
   ```bash
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```
   Verify with `free -h` — should show a `Swap:` line with `2.0Gi` total.
5. **Install tmux** — so long-running sessions/processes survive an SSH disconnect:
   ```bash
   sudo apt install -y tmux
   ```
   Start a session with `tmux new -s main`; reattach later with `tmux attach -t main`.
6. **Basic firewall** (`ufw` isn't preinstalled on this image — install it first):
   ```bash
   sudo apt install -y ufw
   sudo ufw allow OpenSSH
   sudo ufw enable
   ```
   Confirm with `y` when prompted about disrupting the current SSH session — allowing OpenSSH first prevents an actual lockout.
   > Note: this only configures the OS-level firewall. OCI also has its own network-level firewall (VCN Security List / Network Security Group) in front of it — opening a new port later (e.g. WireGuard's, or the app's API) will likely need **both** `ufw allow <port>` *and* a Security List rule in the OCI Console. See section 8 for a real instance of this gotcha.
7. **Verify everything held:**
   ```bash
   free -h && sudo ufw status
   ```

Not done by this script: installing dev tooling like Claude Code/git. The backend is installed by the in-app setup wizard, or by [`app/backend/deploy.sh`](../app/backend/deploy.sh). Its systemd unit is [`infra/scripts/archangel.service`](scripts/archangel.service) (the app bundles a synced copy; see [`scripts/sync_setup_assets.sh`](../scripts/sync_setup_assets.sh)).

## 8. WireGuard VPN Setup

The Archangel API (`app/backend`) is designed to be reachable **only** over a WireGuard tunnel, never the public internet directly (see the backend's architecture plan — "the connection needs to be ultra secure"). This section sets up the WireGuard side of that; the Go binary itself isn't deployed yet.

**Scripted:** [`infra/scripts/wireguard_setup.sh`](scripts/wireguard_setup.sh)
```bash
./infra/scripts/wireguard_setup.sh
```
- Generates a server keypair and one peer keypair per device in the script's `PEERS` array (currently `phone`, `mac`, `windows` — edit the array to add/remove devices)
- Writes `/etc/wireguard/wg0.conf` (server) and one `.conf` per device, all `chmod 600`
- **Refuses to run if `/etc/wireguard/wg0.conf` already exists** — re-running it would regenerate every key and silently break every already-paired device. Pass `--force` if you genuinely want to regenerate everything (all devices then need to re-import their configs).
- Every generated key is verified non-empty (and, in testing, verified to actually round-trip correctly through `wg pubkey`) before being written into a config — see the incident notes below for why this check exists.
- Starts the tunnel (`wg-quick@wg0`) and opens `51820/udp` in `ufw`
- Detects and fixes the pre-`ufw` catch-all-reject gotcha described below (incident note 3) via [`allow_port_before_reject.sh`](scripts/allow_port_before_reject.sh), and makes that fix survive a reboot via [`ensure_boot_fw_fixup.sh`](scripts/ensure_boot_fw_fixup.sh) — both safe no-ops on a box that doesn't have this quirk. `app/backend/deploy.sh` calls the same two shared scripts for the backend's own port, since it hits the identical problem

Applied to `Archangel-Mk1` on 2026-09-02: server on `10.10.0.1/24`, three peers on `10.10.0.2` (phone), `10.10.0.3` (mac), `10.10.0.4` (windows). Verified fully working end-to-end: `wg show` shows a real handshake, `ping 10.10.0.1` succeeds from a paired device, and every piece of the setup (swap, `ufw`, `wg-quick@wg0`, the iptables fix below) confirmed `systemctl is-enabled` = `enabled`, i.e. actually persists across a reboot, not just working until the next restart.

**Pairing a device:**
- **Phone:** `sudo qrencode -t ansiutf8 < /etc/wireguard/phone.conf`, scan the printed QR with the official WireGuard app (**+** → **Scan from QR code**)
- **Mac / Windows:** the `.conf` files can't be scanned — they need to be transferred off the server (they contain a private key, so never paste their contents into chat/Slack/etc; use `scp` or a similar direct transfer), then imported into the WireGuard desktop app ("Import tunnel(s) from file...")

**Required OCI Console step (easy to miss):** `ufw` only controls the box's own OS-level firewall. OCI has a separate network-level firewall (VCN Security List) in front of that, and it does **not** automatically open just because `ufw` did. Add an ingress rule: instance → **Subnet** → **Security Lists** → default list → **Add Ingress Rule** — Source CIDR `0.0.0.0/0`, Protocol `UDP`, Destination Port `51820`. Without this, the tunnel will show as configured correctly on the server but no external device will ever be able to connect — traffic gets dropped before it reaches `ufw` at all.

**Incident notes (why the scripts are this defensive):** getting this actually, fully working — including later deploying the backend onto the same box — hit five real, silent failures worth remembering:

1. `wg genkey | tee /etc/wireguard/x_private.key | wg pubkey | sudo tee ...` — only the second `tee` had `sudo`; the private key `tee` failed permission-denied and the key was lost, without the pipeline itself failing loudly (the public key still computed correctly since it was piped through in memory regardless of the failed write).
2. A `sudo` credential cache expired mid-setup (between separate commands run several minutes apart while working through this interactively), causing a later `$(sudo cat server_public.key)` inside a variable assignment to silently return empty — which then got written into multiple device config files as a blank `PublicKey =` line, with no error at any point.
3. Even with correct keys, correct `ufw` rules, and the correct OCI Security List rule, `ping 10.10.0.1` still failed with zero WireGuard handshake. `ufw status` and `ss -ulnp` both looked completely correct. The actual cause: this OCI Ubuntu image ships a pre-existing iptables ruleset in the raw kernel `INPUT` chain — separate from and evaluated **before** `ufw`'s own chains — allowing only established/related traffic, ICMP, loopback, and new TCP/22, then a catch-all `REJECT`. Diagnosed via `sudo tcpdump -ni any udp port 51820` (packets genuinely arriving at the NIC) followed by `sudo iptables -L INPUT -n -v --line-numbers` (the `ufw-*` chains sitting at 0 hits while the REJECT rule's counter climbed).
4. **The fix for #3 broke something bigger.** `sudo apt install -y iptables-persistent` (used at the time to persist the fix) silently **removed the `ufw` package entirely** — confirmed via `/var/log/apt/history.log`, which shows `Install: iptables-persistent ... / Remove: ufw` in the exact same transaction. `ufw` and `iptables-persistent` conflict at the Debian packaging level (both want to own boot-time iptables rule loading); `apt`'s dependency resolver silently auto-removed the loser, with zero visible warning. This broke the backend deploy later (port `8443` was never reachable) before anyone noticed `ufw` was gone (`dpkg -l` showed it in state `rc` — removed, config retained). **Fix: never install `iptables-persistent` at all** — it isn't needed (see #5).
5. **The real, full root cause of #3 turned out to be deeper than first diagnosed**, discovered while re-verifying after fixing #4. `ufw`'s config files survived the removal and were correctly restored on reinstall (`ufw status` looked completely normal again) — but the backend's port was *still* silently rejected. `sudo nft -a list chain ip filter INPUT` (the authoritative live ruleset, not the `iptables -L` compatibility view — which was independently confirmed unreliable here, reporting a duplicate/stale REJECT rule that the real `nft` state proved never existed) revealed the actual structure: `ufw`'s entire inbound rule chain (`ufw-before-input` and friends) is **unreachable dead code**, positioned *after* the pre-existing catch-all `REJECT` in the flat `INPUT` chain, which terminates processing before anything ever reaches it. This isn't a `ufw`-vs-catch-all *ordering* bug exactly — it's that the two rule sets were never actually wired together at all; `ufw`'s own machinery has simply never been reachable on this box, for any port, the whole time. The fix (a plain `nft insert rule ip filter INPUT handle <N> <proto> dport <port> accept`, positioned immediately ahead of the real reject rule's handle) is now [`allow_port_before_reject.sh`](scripts/allow_port_before_reject.sh), shared by both `wireguard_setup.sh` and `app/backend/deploy.sh` since both need it for their own port. Because this is a live, in-kernel-only change with nothing found that reapplies it (or the original catch-all rule) at boot, [`ensure_boot_fw_fixup.sh`](scripts/ensure_boot_fw_fixup.sh) installs a small systemd oneshot service that reruns it, for every registered port, on every boot.

All five are exactly the class of bug that "did it print an error?" doesn't catch. The scripts' `require_nonempty`/re-verification checks throughout, running as continuous scripts (no time gap for a sudo cache to expire), never installing `iptables-persistent`, using `nft` with stable rule handles instead of fragile `iptables -L` line numbers, and now reapplying the fix at every boot rather than trusting a one-time persistence mechanism — all exist specifically because of this.

## 9. Master Setup Script

[`infra/scripts/install-archangel.sh`](scripts/install-archangel.sh) is the canonical "how do I set this box up" entrypoint — a thin orchestrator that runs `baseline_setup.sh` then `wireguard_setup.sh` in order (skipping WireGuard if it's already configured, to protect existing pairings). For a genuinely fresh instance:

```bash
git clone https://github.com/dwaipayanray95/Project-Archangel.git && cd Project-Archangel
./infra/scripts/install-archangel.sh
```

It's meant to keep growing as new milestones land — deploying `app/backend`'s binary + systemd unit becomes a new step here once that deployment tooling exists and is verified, rather than being written speculatively ahead of time.

## 10. Related / Future Projects

- **Archangel control app** — decided: a **Go backend** (single static binary, SSH bridge + resource watchdog + file browser, holds real SSH credentials server-side) plus a **Flutter frontend** (Android-first, one Dart codebase with iOS/web reach later). The app authenticates to the Go API with its own token — it never touches the SSH key directly. Lives in `app/` at the repo root (see the root [`README.md`](../README.md)) and is built and working.
- Possible future use cases for the VPS(es): self-hosted WireGuard VPN, backend/staging host for other personal app projects, personal automation projects (finance tracking, uptime monitoring, morning dashboard, etc.)

---
*Last updated: 2026-09-11*
