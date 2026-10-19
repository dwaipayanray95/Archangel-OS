# Security

How Archangel protects your server, and, just as important, where the limits are. We try to be honest here.

To report a vulnerability, see [SECURITY.md](../SECURITY.md).

## The short version

- Your server's Archangel program is **not on the public internet**. It is reachable only through an encrypted WireGuard tunnel.
- Each device has **its own key and token**, and you can **revoke** one at any time.
- **A device that is paired is powerful.** If someone gets your unlocked phone or laptop with Archangel on it, they can control your server. Protect your devices.

## Layers of protection

| Layer | What it does |
|---|---|
| **Provider firewall** | You open only UDP 51820 (the tunnel), plus SSH (TCP 22) which the wizard needs. |
| **WireGuard tunnel** | Encrypted. A device without the right key gets no answer at all. |
| **Private listen address** | `archangeld` listens only on the tunnel address (`10.10.0.1`). |
| **Per-device token** | Every request needs a token. The server keeps only a hash of it. |
| **Limited user** | `archangeld` runs as a normal user named `archangel`, not as root. |
| **Admin mode switch** | Decides whether that user may use `sudo`. See below. |
| **Checked updates** | The server program is downloaded with a checksum check, and rolled back if it fails to start. |

## What a token can do (the honest part)

A token lets a device use the Archangel API: the **terminal**, files, Docker, services and more.

- **With Admin mode on (the default):** the terminal can run `sudo` with no password. So **a token is effectively root on your server.** Whoever has a valid token plus tunnel access can do anything.
- **With Admin mode off:** the terminal runs as the limited `archangel` user. That removes `sudo`, but be aware of two things:
  - That user can use **Docker** (the setup adds it to the `docker` group), and Docker access can be turned into root access by someone who knows how. So Admin mode off makes things harder, not impossible.
  - It can read and write everything in its own home folder (`/home/archangel`), including your files and Caddy's settings.

So: Admin mode off is a good safety step if you don't need `sudo`, but **do not think of it as a hard wall.**

### Why a stolen token alone is not enough

An attacker needs both:

1. the device's **tunnel key** (to get onto the private network), and
2. the device's **token** (to use the API).

Both live in the same pairing, on the same device. If someone takes your device, they get both.

## Admin mode

- **On by default** after setup.
- **Off from the app:** Settings → Admin mode. Takes effect right away.
- **On again needs your SSH key.** The server's API never allows turning it on. This is on purpose: a stolen token can lower privileges, but never raise them.

More in [How it works](how-it-works.md#admin-mode).

## Remove a device you no longer trust

1. Open **Settings → Devices**.
2. Tap **Revoke** next to the device, and type its name to confirm.

This deletes the device's token and removes its tunnel key from the server. It stops working immediately. This needs Admin mode on. If Admin mode is off, either turn it on first, or do it on the server:

```bash
sudo archangeld devices          # list paired devices
sudo archangeld unpair my-old-phone
```

If you lost a device, revoke it first, then think about whether anything on the server was exposed.

## Keep your devices safe

- Use a **screen lock** on your phone and laptop.
- Keep your **operating system** updated.
- Don't install the app on a device you don't control.
- Keep a pairing code private. It contains the device's tunnel key and token. It is shown once, so don't screenshot or save it in chat.
- Revoke devices you stopped using.

## Your SSH key

The setup wizard uses your SSH key to sign in once. You can tick **Remember this key on this device** so the app can update or fix the server later.

- A saved key is **encrypted with a passphrase you choose** (at least 8 characters). The passphrase is not stored. If you forget it, the saved key cannot be recovered. Just paste the key again.
- Without "Remember", the key is not kept.
- Best practice: use a key made just for this server, not one you use everywhere.
- Keep your private key in a password manager or other safe place. Never put it on the server.

What the app saves for each server (tunnel config and token) is stored in the app's data folder on your device, readable only by your user account. It is not encrypted with a passphrase. That's why your **device lock** matters.

## Apps you run

- Apps are **private by default**. Only your devices can reach them.
- Choosing **Public** exposes that port to the whole internet (if your provider's firewall also allows it). Only do that for software you trust and keep updated.
- Caddy (web addresses) uses ports 80 and 443, which the setup opens in the server's firewall. It only serves addresses you set up.

## Known limits

- This is built for **one person or a small trusted group**. All paired devices have the same level of access.
- There are no per-device permissions yet.
- The app is not signed with paid certificates for macOS and Windows. Download only from the project's GitHub Releases.
- The first connection trusts the server's SSH fingerprint ("trust on first use"). The app warns you if it later changes.

Found something? [SECURITY.md](../SECURITY.md).
