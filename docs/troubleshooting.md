# Troubleshooting

Find your problem, try the fix. Setup is safe to run again if it fails, so don't be afraid to retry.

**Jump to:**
[Setup wizard](#setup-wizard-problems) ·
[Can't reach your server](#the-app-says-cant-reach-your-server) ·
[Terminal](#the-terminal-says-temporary-shell) ·
[Admin mode](#admin-mode-is-off-errors) ·
[Apps](#my-app-isnt-reachable) ·
[Logs](#how-to-see-the-logs-on-the-server) ·
[Re-pair](#how-to-re-pair-a-device) ·
[Uninstall](#how-to-uninstall)

---

## Setup wizard problems

The wizard shows what went wrong in plain words and offers **Retry**. "Technical details" shows the raw message.

| What you see | What it means | Fix |
|---|---|---|
| "The server refused your key" | Wrong username, or the key doesn't match what the server has. | Check the **username**: `ubuntu` for Oracle Cloud Ubuntu, `root` for Hetzner and DigitalOcean. Check that you pasted the **private** key (not the `.pub` file) and that it is the one you added when you created the server. |
| "Archangel could not read that key" | The key text is incomplete or locked. | Paste the whole key including the `-----BEGIN` and `-----END` lines, or pick the key file. If the key has its own passphrase, enter it in the passphrase box. |
| "Could not reach the server" (connection refused, timed out, no route) | The app can't open an SSH connection. | Check the **IP address** for typos. Check that **TCP port 22** is open in your provider's firewall. Check the server is running. |
| "The private secure connection could not be set up or reached" (WireGuard, handshake, tunnel, 51820) | The tunnel can't connect. | Open **UDP port 51820** in your provider's firewall. This is separate from the server's own firewall. See your [provider guide](getting-started.md#2-get-a-server). Then retry. |
| "This user is not allowed to run administrator commands without a password" | The username can't use `sudo` without a password. | Use `ubuntu` (Ubuntu images) or `root`. |
| "This server type is not supported" | Not Ubuntu/Debian, or an unusual chip. | Create a new server with Ubuntu 22.04 or 24.04. |
| "The server's identity could not be confirmed" | The server's SSH fingerprint is different from one the app saw before. | If you rebuilt the server on the same IP, this is expected. If you didn't, stop and be careful: someone may be in the way. |
| "The server could not download Archangel" | The server can't reach GitHub, or the file failed its checksum. | Wait a few minutes and retry. Check that the release exists on GitHub. |

**Tunnel won't connect even though 51820 is open?** On the server, run `sudo wg show`. If you see a `latest handshake` line for a peer, the tunnel works. If not, the provider firewall is still blocking UDP 51820, or your device's network blocks UDP (some hotel or work networks do). Try another network, like phone data.

---

## The app says "Can't reach your server"

The app talks to your server through the tunnel. Check, in this order:

1. **Is the tunnel on?** In Settings, check the Tunnel card. Turn the secure connection on.
2. **Is your internet working?** Try another network (Wi-Fi vs phone data).
3. **Is the server running?** Check your provider's control panel. Start it if it is off.
4. **Is UDP 51820 still open** in the provider's firewall? A changed firewall can close it.
5. **Is the Archangel service running?** Sign in with SSH and run:
   ```bash
   sudo systemctl status archangel
   ```
   If it isn't active, run `sudo systemctl restart archangel`, then read the [logs](#how-to-see-the-logs-on-the-server).
6. **Was the device removed?** If this device was revoked from another device, its token and tunnel key no longer work. [Re-pair](#how-to-re-pair-a-device).
7. **Did the server's public IP change?** Some providers change the IP if you delete and recreate a server. Then you need to set it up again.

The Archangel health check (`/api/v1/health`) only answers inside the tunnel. That's why a working internet connection alone isn't enough.

---

## The terminal says "temporary shell"

You see a banner like "Persistent sessions unavailable ... using a temporary shell".

**What it means:** the server couldn't start **tmux** (the program that keeps sessions alive). The terminal still works, but it ends when you close it, and you can't come back to it.

**Fix:** the server is probably missing `tmux` or `dbus-user-session`.

1. In the app, open **Settings → This server**. Tap **Update** if an update is offered, otherwise tap **Repair server permissions**. The app signs in over SSH and installs the missing pieces.
2. Open a new terminal session.

Or fix it by hand on the server:

```bash
sudo apt-get update
sudo apt-get install -y tmux dbus-user-session
sudo loginctl enable-linger archangel
sudo systemctl restart archangel
```

---

## "Admin mode is off" errors

You see "Admin mode is off - this action needs it" when you reboot the server, restart a service, add or revoke a device, or run `sudo` in the terminal.

**What it means:** Admin mode was turned off, so those actions are blocked on purpose. See [How it works](how-it-works.md#admin-mode).

**Fix, if you want it back:** In **Settings → Admin mode**, switch it on. The app asks for your SSH key (it can't be turned on through the app's normal connection, by design). Then try again.

**If you want it to stay off:** that's fine. Use SSH from another tool for those actions.

---

## My app isn't reachable

You ran an app (like `nginx`) but you can't open it in a browser.

- **Apps are private by default.** A port set to **Private** is only reachable by your devices **through the tunnel**, at the server's tunnel address (`10.10.0.1`). Make sure the secure connection is on, then open `http://10.10.0.1:<port>`. Don't use the public IP.
- **Want it public?** Set the port to **Public** when you run the app. Then the provider's firewall must also allow that port (TCP, or UDP if the app uses UDP). This exposes the app to the whole internet, so only do it for apps meant to be public. See [Security](security.md).
- **Want a web address?** Use **Services → Web addresses** (Caddy). You need a domain name pointing at your server, and ports 80 and 443 open at the provider.
- **Is the app running?** Check the status in **Apps** and read its logs.
- **Is the port right?** The app's own port inside the container may differ from the port you published.

---

## How to see the logs on the server

Sign in with SSH:

```bash
ssh -i /path/to/your/private-key ubuntu@YOUR_SERVER_IP
```

(Use `root` instead of `ubuntu` on Hetzner and DigitalOcean.) Then:

| What | Command |
|---|---|
| Last 100 lines of the Archangel server log | `sudo journalctl -u archangel -n 100` |
| Follow it live (Ctrl+C to stop) | `sudo journalctl -u archangel -f` |
| Is the service running? | `sudo systemctl status archangel` |
| Is the tunnel up? | `sudo wg show` |
| Who is paired? | `sudo archangeld devices` |

---

## How to re-pair a device

Use this when a device was revoked, you lost the pairing, or the app can't connect with its saved token.

1. On a device that already works, open **Settings → Devices → Add a device** and create a code. Or, on the server over SSH:
   ```bash
   sudo archangeld pair my-new-device
   ```
2. On the device that needs pairing: **Add a server → I have a pairing code**, then scan or paste the code.

The name must be unused. If the old entry is still there, remove it first:

```bash
sudo archangeld unpair old-device-name
```

If no device works any more, sign in over SSH and run `sudo archangeld pair <name>`. That only needs your SSH key.

---

## How to uninstall

**From the app:** open **Settings → Danger zone → Uninstall backend**. Type the confirmation. The app signs in over SSH and removes the Archangel service, its files, and WireGuard from the server. Then it forgets that server.

**What stays:** the system updates, swap file, Docker, Caddy, tmux and firewall changes the setup made. Those are normal tools and are left alone. Your apps and their data in Docker are not deleted.

**To stop paying for the server:** delete it in your provider's control panel. That removes everything.

On your devices, you can also remove the app and, if you used the WireGuard app, any leftover tunnel.

---

Still stuck? Open an issue at <https://github.com/dwaipayanray95/Archangel-OS/issues> and include the "Technical details" text (remove any secrets first). For security problems, use [SECURITY.md](../SECURITY.md) instead.
