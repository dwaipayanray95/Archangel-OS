# How it works

A plain explanation of what Archangel installs, what runs where, and why it is safe by default. No Linux knowledge needed.

## The big picture

```
 Your devices                                   Your server (a rented Ubuntu VPS)
 ------------                                   ---------------------------------

 +-----------+                                  +------------------------------+
 | Phone     |  10.10.0.2                       |  WireGuard      10.10.0.1    |
 | (app)     |-----+                            |       |                      |
 +-----------+     |                            |       v                      |
                   |   encrypted WireGuard      |  archangeld (port 8443)      |
 +-----------+     |   tunnel over the          |   - terminal (via tmux)      |
 | Laptop    |-----+==== internet ==============>   - files                    |
 | (app)     |  10.10.0.3   UDP 51820           |   - system stats             |
 +-----------+                                  |   - Docker + services        |
                                                |                              |
                                                |  Docker (your apps)          |
                                                |  Caddy  (web addresses)      |
                                                +------------------------------+
```

Three ideas:

1. **A private network.** Archangel creates a tiny private network (`10.10.0.x`) between your devices and your server, using WireGuard. The server is always `10.10.0.1`. Your devices get `10.10.0.2`, `10.10.0.3` and so on.
2. **The server program only listens on that private network.** `archangeld` (the Archangel server program) listens on `10.10.0.1:8443`. That address does not exist on the public internet. You can only reach it through the tunnel.
3. **Each device has its own key and token.** A device needs both a tunnel key and an app token. Take either away and it cannot get in.

## What runs where

**On your devices:** the Archangel app. It stores, for each server, the tunnel settings and that device's token. It can also keep your SSH key, locked with a passphrase you choose, if you tick "Remember this key".

**On your server** (installed by the setup wizard):

| Program | What it does | Who can reach it |
|---|---|---|
| **WireGuard** (`wg0`) | The private tunnel. | The internet, on **UDP 51820**, but it only answers devices with a valid key. |
| **archangeld** | The Archangel server: terminal, files, system stats, Docker control, services. Runs as an unprivileged user called `archangel`. | Only through the tunnel (`10.10.0.1:8443`). |
| **Docker** | Runs your apps in containers. | Apps are private by default. See [below](#apps-private-by-default-public-on-request). |
| **Caddy** | A web server that can give your apps web addresses. | Ports 80 and 443 are open in the server's firewall for it. |
| **tmux** | Keeps terminal sessions alive. | Local only. |
| **ufw** | The server's own firewall. | n/a |

## Why nothing is exposed to the internet

- The setup wizard asks you to open **only UDP 51820** in your provider's firewall (plus SSH on port 22, which providers normally open already, and which the wizard uses).
- WireGuard is silent to strangers. A device without the right key gets no reply at all.
- The Archangel server is not listening on the public address. Even if its port were opened by mistake, it would not be there to answer.
- Every request still needs a valid token, on top of the tunnel.

The server's own firewall also opens ports 80 and 443 for Caddy. Caddy only serves addresses you set up yourself.

## Tokens: one per device

When you pair a device, the server makes:

- a new **WireGuard key pair** and tunnel address for it, and
- a new random **token** for the app to prove who it is.

The server stores only a **hash** of the token (a one-way scramble), never the token itself. The device keeps the real token.

Each device has its own name. In **Settings** you can see the list, and **revoke** a device. Revoking deletes its token and removes its tunnel peer, so it loses access immediately.

## Admin mode

Linux has a powerful account called **root**. Commands that change the system (installing programs, restarting services, rebooting) need root. The command `sudo` means "run this as root".

`archangeld` runs as a normal, limited user called `archangel`. **Admin mode** means that user is allowed to use `sudo` without typing a password. The grant is a file on the server: `/etc/sudoers.d/archangel`.

| | Admin mode **on** | Admin mode **off** |
|---|---|---|
| Terminal | You can run `sudo` commands. | `sudo` is refused. |
| App actions that need root (reboot, restarting some services, revoking a device, adding a device from the app) | Work. | Fail with "Admin mode is off - this action needs it". |
| Reading stats, files, running apps you own | Work. | Work (as far as the limited user is allowed). |

Rules:

- **On by default** after setup.
- **You can turn it off from the app** (Settings → Admin mode). The server deletes the sudoers file.
- **Turning it on needs your SSH key.** The server's own API refuses to turn it on, so a stolen app token can only lower privileges, never raise them. The app does it over SSH with your key.

Admin mode matters because it changes what a leaked token could do. See [Security](security.md).

## Persistent terminal sessions

Normally, a terminal ends when you disconnect. Archangel uses **tmux**, a program that keeps your shell running on the server. So:

- Close the app, lose Wi-Fi, switch phones: your session is still there.
- Restart the Archangel server program: your session is still there.
- Open the Terminal again and you reconnect to where you were.

You can have several named sessions (the app lists them, and you can end one). The server allows up to 3 open terminal connections at once, and closes one that sits idle for 10 minutes.

If tmux cannot start, the terminal falls back to a **temporary shell** and shows a banner saying so. That shell ends when you disconnect. See [Troubleshooting](troubleshooting.md#the-terminal-says-temporary-shell).

## Updates

- **The app** checks GitHub Releases and tells you when a newer version exists.
- **The server program** is updated from the app: tap the update badge next to the backend version in Settings. The app signs in over SSH (using your remembered key, or asks for one), then:
  1. makes a backup of the current `archangeld`,
  2. downloads the new one and **verifies its SHA-256 checksum** against the release's `SHA256SUMS` file,
  3. restarts the service,
  4. waits for the new version to answer a health check,
  5. **rolls back to the backup automatically** if it doesn't come up.

The server program deliberately cannot update itself through its API. That means a leaked token cannot swap the program for a malicious one.

## Apps: private by default, public on request

You run apps from **Apps** as Docker containers. For each port an app uses, you choose:

| Choice | Who can reach it |
|---|---|
| **Private** (default) | Only your devices, on the tunnel address (`10.10.0.1`). |
| **Public** | Anyone on the internet, if the provider's firewall also allows that port. |

Docker normally publishes ports to everyone and skips the server's firewall. Archangel avoids that by publishing to the tunnel address unless you name a public one.

To put an app on a real web address, use **Services → Web addresses** (Caddy). That needs ports 80 and 443 open at your provider, and a domain name pointing at your server.

## What gets installed where

| Path on the server | What |
|---|---|
| `/opt/archangel/archangeld` | The server program (also linked as `archangeld` in the command path). |
| `/etc/archangel/config.yaml` | Its settings. |
| `/etc/archangel/tokens.json` | Device names and token hashes. |
| `/etc/wireguard/wg0.conf` | The tunnel settings. |
| `/etc/sudoers.d/archangel` | The Admin mode grant, if on. |
| `/home/archangel` | The home folder. The Files screen is limited to this folder by default. |
| `/etc/systemd/system/archangel.service` | Starts `archangeld` on every boot. |

Next: [Security](security.md) · [Troubleshooting](troubleshooting.md)
