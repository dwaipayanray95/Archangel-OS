# Getting started

This guide takes you from nothing to your own private cloud in about 15 minutes (plus a few minutes of waiting). No Linux knowledge needed.

**What you will do:**

1. Get the app
2. Get a server
3. Open one door in the provider's firewall
4. Run the setup wizard
5. Use your server

---

## What you need

| Thing | What it is | Where to get it |
|---|---|---|
| **A server (VPS)** | A small always-on computer you rent. "VPS" means virtual private server. It can be free. | [Oracle Cloud](guides/oracle-cloud.md) (free), [Hetzner](guides/hetzner.md), [DigitalOcean](guides/digitalocean.md) |
| **Ubuntu 22.04 or 24.04** | The operating system on the server. Pick it when you create the server. | Choose it in your provider's "create server" screen. |
| **An SSH key** | A pair of files that works like a very strong password. The app uses it once to set up your server. | Your provider can make one for you, or see [SSH keys in plain words](#ssh-keys-in-plain-words) below. |
| **The Archangel app** | On your phone or laptop. | See step 1. |

The server must be a normal Intel/AMD (x86_64) or ARM server. Archangel's setup wizard only supports Ubuntu or Debian.

---

## 1. Download the app

Go to the **Releases** page of the project on GitHub:
<https://github.com/dwaipayanray95/Project-Archangel/releases>

Download the file for your device:

| Your device | Download | Notes |
|---|---|---|
| Mac | `Archangel-macos.dmg` | Open it and drag **Archangel** to **Applications**. |
| Windows | `Archangel-windows-setup.exe` | Run the installer. Windows may ask for administrator permission when the app starts. It needs this to create the private connection. |
| Android | `app-arm64-v8a-release.apk` | For modern 64-bit (ARM64) phones. See below. |

> Not every release contains every app. If the newest release has no file for your device, look at the next older release.

### Mac: "Archangel can't be opened"

The app is not signed with a paid Apple developer certificate, so macOS is cautious the first time.

1. Try to open Archangel. macOS says it can't verify the app. Click **Done** (not "Move to Bin").
2. Open **System Settings** → **Privacy & Security**.
3. Scroll down to the message about Archangel and click **Open Anyway**.
4. Confirm. You only need to do this once.

(On older macOS versions, you can also right-click the app, choose **Open**, then **Open** again.)

### Android: "Install unknown apps"

The `.apk` is not from the Play Store, so Android asks permission first.

1. Open the downloaded `.apk` file.
2. Android says your phone isn't allowed to install unknown apps from this source. Tap **Settings**.
3. Turn on **Allow from this source** for your browser (or file manager).
4. Go back and tap **Install**.

You can turn that permission off again afterwards.

### Windows: "Windows protected your PC"

If you see a blue SmartScreen box, click **More info**, then **Run anyway**. This appears because the installer is not signed with a paid certificate.

---

## 2. Get a server

Pick one guide and follow it. Each one ends with you having a server's **IP address** and the **username** to sign in with.

- [Oracle Cloud Always Free](guides/oracle-cloud.md): free, but popular regions can be full
- [Hetzner](guides/hetzner.md): about 4 to 5 euros a month
- [DigitalOcean](guides/digitalocean.md): about 6 US dollars a month

Write down:

- the **IP address** (like `203.0.113.5`)
- the **username** (`ubuntu` on most providers)
- where your **private key file** is

---

## 3. Open the provider firewall (UDP 51820)

This is the one thing the app cannot do for you.

**Why?** Archangel connects your devices to your server through a private, encrypted tunnel (WireGuard). That tunnel uses **UDP port 51820**. Your provider has a firewall in front of your server that blocks almost everything by default. If port 51820 is blocked, the tunnel can never connect. The provider guides show exactly where to click.

Also make sure **port 22 (TCP)** is open. That is what the setup wizard uses to sign in. Most providers open it by default.

You do **not** need to open any other port. The Archangel server is only reachable through the tunnel. See [How it works](how-it-works.md).

---

## 4. Run the setup wizard

1. Open the Archangel app. Tap **Add a server**, then **Yes, set it up for me**. (If you have no server yet, **Not yet** shows the provider guides.)
2. Follow the screens. Each one is one question:

| Screen | What to enter |
|---|---|
| **Where is your server?** | The IP address and the username. |
| **Your SSH key** | Paste your private key, or pick the key file. Use the file **without** `.pub`. If the key has its own passphrase, enter it. You can tick "Remember this key on this device"; the app then asks you to choose a passphrase to lock it. |
| **Name this device** | Any name you will recognise, like `my-phone`. |
| **Advanced** (optional) | Ports and the private network. The defaults (UDP 51820, server port 8443, network 10.10.0) are right for almost everyone. |
| **Before you start** | A summary of what will happen. Check the firewall reminder, then start. |

3. Wait. It takes **about 5 to 10 minutes**. Keep the app open. It is safe to run again if anything fails.

### What the wizard does

The app signs in over SSH and does these steps for you:

| Step | In plain words |
|---|---|
| Connecting to your server | Signs in with your SSH key. The first time, it asks you to confirm the server's fingerprint. |
| Checking the server is supported | Needs Ubuntu or Debian, and an Intel/AMD or ARM chip. |
| Copying the setup scripts | Sends the install scripts to the server. |
| Installing updates and the firewall | Updates the system, adds some swap memory, installs tmux, Docker and Caddy, and turns on the server's own firewall. |
| Setting up a private secure connection | Installs WireGuard and creates the tunnel. |
| Installing Archangel | Downloads the Archangel server program (`archangeld`) from GitHub and checks its checksum. |
| Writing the server settings | Creates the config file. |
| Starting the Archangel server | Installs it as a service that starts on every boot. |
| Opening the app port to your private connection | Allows the server port only on the tunnel. |
| Pairing this device | Creates this device's keys and token and connects it. |

If a step fails, the app tells you what went wrong in plain words and offers to try again. See [Troubleshooting](troubleshooting.md).

---

## 5. What you see afterwards

The wizard ends with **Your server is ready**. Tap **Open your server**. You land on **Home**.

- **Home**: how your server is doing.
- **Apps**: run your first app. Try the image `nginx`.
- **Files**: browse files.
- **Terminal**: a command line on your server.
- **Activity**: charts and running programs.
- **Services**: background programs and web addresses.
- **Settings**: devices, Admin mode, updates.

**Admin mode is on** after setup. That lets the terminal and the app run administrator commands (`sudo`). You can turn it off any time in Settings. See [Security](security.md).

---

## Add another device

Every phone or laptop that uses your server needs its own pairing. A pairing creates a new tunnel key and a token just for that device.

**From a device that is already paired:**

1. Open **Settings → Devices → Add a device**.
2. Give the new device a name.
3. The app shows a **QR code** and a **pairing code** (a long piece of text).
4. On the new device, install the app, tap **Add a server**, then **I have a pairing code**.
5. Scan the QR code (Android only) or paste the code.

**From the server itself** (if you sign in with SSH):

```bash
sudo archangeld pair my-laptop
```

It prints a pairing code. Paste it into the new device. Add `--qr` to also print a QR code (needs the `qrencode` program on the server).

> A pairing code contains secrets for that device. Share it only with yourself, and don't post it anywhere. It is shown once.

To remove a device later, see [Security](security.md#remove-a-device-you-no-longer-trust).

---

## Next steps

- [How it works](how-it-works.md): what runs where, and why nothing is exposed.
- [Security](security.md): keep your server and devices safe.
- [Troubleshooting](troubleshooting.md): when something goes wrong.

---

## SSH keys in plain words

An SSH key is two files:

- a **private key**: keep it secret, never share it. The app needs this one.
- a **public key** (ends in `.pub`): safe to share. You give this one to the provider so the server trusts you.

If your provider generates a key for you, it gives you the private key to download. Save it somewhere safe, like a password manager.

To make your own on a Mac or Windows 10/11 terminal:

```bash
ssh-keygen -t ed25519
```

It creates the two files (by default in a `.ssh` folder in your home folder: `id_ed25519` and `id_ed25519.pub`). Upload the **`.pub`** file to your provider.
