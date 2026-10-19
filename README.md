# Archangel OS

*Your private cloud, guarded 24/7.*

**Archangel OS turns a rented server into your own private cloud.** Set it up, manage it, and use it from your phone or laptop. No Linux knowledge needed.

You rent a small server (it can be free), give the Archangel app its address, and it installs everything for you. It installs on top of your existing Ubuntu server — no reinstalling the server's operating system, and nothing you already run there is replaced. After that you can run apps, browse files, open a terminal and watch your server's health, all over a private, encrypted connection that only your own devices can use.

> **Source-available, not open source.** See [License](#license).

---

## What you can do

| Screen | What it does, in plain words |
|---|---|
| **Home** | One glance: is my server healthy? Shows CPU, memory and disk in plain words, and a "needs attention" list. |
| **Apps** | Run, stop, restart and remove apps (they run in Docker containers). Read their logs. Choose whether an app is private or public. |
| **Files** | Browse, preview and download files on your server. |
| **Terminal** | A real command line on your server. Sessions keep running when you close the app, and you can come back to them. |
| **Activity** | Live charts of CPU, memory, disk and network, plus the list of running programs. |
| **Services** | The programs that run in the background, scheduled jobs, web addresses (Caddy) and your own scripts. |
| **Settings** | Your devices, Admin mode, updates, appearance, saved SSH key, and removing Archangel. |

Also:

- **Private, secure connection.** Your devices talk to the server through a [WireGuard](https://www.wireguard.com/) tunnel. The Archangel server is not exposed to the internet. ([How it works](docs/how-it-works.md))
- **Multiple servers.** Add as many servers as you like and switch between them.
- **Admin mode.** A switch that decides whether the app and terminal may run powerful "administrator" commands (`sudo`). On by default, and you can turn it off from the app. ([Details](docs/security.md))
- **One-tap setup.** A setup wizard installs and configures everything over SSH. Updates are checksum-verified and roll back automatically if something goes wrong.

## Screenshots

<!-- TODO: add screenshots (Home, Apps, Terminal, setup wizard) to docs/images/ and show them here. -->

Coming soon.

## Get started in 15 minutes

You need a server running Ubuntu, an SSH key, and the app. The step-by-step guide is here:

**[Getting started](docs/getting-started.md)**

### Download

Get the app from the [Releases page](https://github.com/dwaipayanray95/Archangel-OS/releases/latest):

| Device | File |
|---|---|
| Mac | `Archangel-macos.dmg` — open it, drag **Archangel** into **Applications** |
| Windows | `Archangel-windows-setup.exe` |
| Android | `Archangel-android.apk` — allow "install unknown apps" when asked |

**Mac users:** the app isn't signed by Apple yet, so macOS will say it's "damaged" or "can't be opened". After moving it to Applications, run this once in the Terminal app (it asks for your Mac password):

```bash
sudo xattr -d com.apple.quarantine /Applications/Archangel.app
```

Then open Archangel normally. More detail in [Getting started](docs/getting-started.md#mac-archangel-is-damaged-or-cant-be-opened).

No server yet? Pick a provider guide:
[Oracle Cloud (free)](docs/guides/oracle-cloud.md) ·
[Hetzner](docs/guides/hetzner.md) ·
[DigitalOcean](docs/guides/digitalocean.md)

Something not working? See [Troubleshooting](docs/troubleshooting.md).

## How it's built

- **The app** is written in Flutter (Dart). One codebase for macOS, Windows and Android.
- **The server program**, `archangeld`, is written in Go. It is one small file with nothing else to install, and it only listens on the private tunnel address.
- **Setup scripts** (shell) prepare a fresh Ubuntu server: updates, firewall, Docker, Caddy, tmux and WireGuard.

More in [How it works](docs/how-it-works.md).

## Project layout

| Folder | What is in it |
|---|---|
| [`app/frontend/`](app/frontend/README.md) | The Flutter app. |
| [`app/backend/`](app/backend/README.md) | `archangeld`, the Go server program (API, terminal, files, Docker, services). |
| [`infra/`](infra/README.md) | Server setup scripts and the manual recovery runbook (Oracle Cloud notes included). |
| [`docs/`](docs/getting-started.md) | User guides, provider guides, troubleshooting and security. |
| [`scripts/`](scripts/sync_setup_assets.sh) | Repo helper scripts. |
| [`.github/workflows/`](.github/workflows) | CI checks and the release pipeline. |
| `VERSION` | The version numbers for the project, the app and the server program. |

## Contributing and security

- Want to help? Read [CONTRIBUTING.md](CONTRIBUTING.md).
- Found a security problem? Please report it privately. See [SECURITY.md](SECURITY.md).
- How Archangel protects you (and where the trade-offs are): [Security model](docs/security.md).

## License

Archangel uses **The Awesome License v1 (TALv1)**. Read the full text in [LICENSE](LICENSE). In short:

- **Free** for personal, educational and open-source projects where no revenue is made.
- **Commercial use** (a revenue-generating project, or use inside or on behalf of a for-profit company) needs one of two things: release your whole project under an OSI-approved open source license, or agree on a commercial license with the author first.
- You must **credit** the original author.

TALv1 is a **source-available** license. It is **not** an OSI-approved open source license. If you are unsure whether your use counts as commercial, read [LICENSE](LICENSE) or contact the author (see the file).
