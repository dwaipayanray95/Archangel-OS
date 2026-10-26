# Spec: Settings

Status: **signed off** by Ray. Built.

Updated per Ray's decision 2026-10-26: keep current sections. This replaces the
earlier structure (Servers, Devices, Admin mode, Security, Appearance, Updates,
Danger zone). The sections below are what the app does now.

Goal: keep every section Settings already has, but arrange it better, explain
each card in one plain line, and replace jargon with useful information.

## Rules for every card

- A card has a **title** (sentence case) and **one plain line** under it saying
  what it is for (`SettingsCard.intro`).
- Long cards are split into groups with small sub-headings
  (`SettingsGroupLabel`), or into several cards, not one long list.
- Plain words: "secure connection", not "WireGuard tunnel"; "apps", not
  "containers". Technical values only appear inside "Technical details".
- Status is icon + text (`StatusBadge`). Risky actions ask first.

## Structure

Sections, in this order:

| id | Label | Icon |
|---|---|---|
| about | About | auto_awesome_rounded |
| servers | Servers | dns_outlined |
| devices | Devices | devices_outlined |
| admin | Admin mode | key_outlined |
| security | Security | shield_outlined |
| appearance | Appearance | light_mode_outlined |
| system | System | tune_rounded |

Hide Devices and Admin mode while no server is paired.

- **Wide** (given width at least 720): a section list on the left (220 wide,
  three glass groups: About / Servers to Security / Appearance and System) and
  the chosen section on the right. It opens on About.
- **Narrow** (under 720, including 340-wide Desktop windows): the list as
  full-width rows with a chevron; tapping one opens it with an "All settings"
  ghost button at the top. Decided with `LayoutBuilder`.

## About

A useful overview of this server. Cards, in order:

1. **Header**: taller Archangel OS banner card featuring the wordmark (size 34),
   tagline "Your private cloud, guarded 24/7.", status chips
   (`(vx.y.z build)`, server guard status or "No server yet", and update readiness
   indicator), and actions:
   - **Updates**: opens the dedicated in-settings Updates subpage.
   - **Changelog**: opens the release notes / changelog on GitHub.
2. **This server** (paired only): "A quick look at the server you are using."
   - Server name (mono) with the health sentence (`evaluateHealth`) and a
     health chip (Healthy / Needs attention / Offline / Connecting).
   - Running for ("3 days 4 hours").
   - Operating system in plain words ("Ubuntu 24.04").
   - Size ("4 CPU cores · 8 GB memory · 80 GB disk").
   - Until the server answers: "Details appear once your server answers."
3. **Secure connection** (paired only): "Everything between this device and your
   server is encrypted."
   - Connection: the shell's words (`connectionText`) and a chip (Encrypted,
     Connecting…, Not answering, Not connected).
   - Private address (mono, for example 10.10.0.7).
   - "Last checked 7s ago" (from the live server readings).
   - **Technical details**: collapsed toggle. Open, it lists computer name,
     kernel, architecture, full OS name, server address, server program
     version, connection endpoint, tunnel address, allowed addresses,
     interface name and both ports. Each value has a copy button (tooltip
     "Copy <label>"). Empty values are left out. The private key is never shown.

### Updates (subpage inside Settings)

Opened from the **Updates** button in the Archangel OS header card. Upon opening,
it automatically triggers a fresh check against GitHub releases.

- Back button: **Back to About** returns to the main About view.
- Card "Updates": "The app and your server share one version."
  - Archangel OS headline row (`Archangel OS <version> (build <n>)`, with server version diff when they differ).
  - Status chip ("Up to date" or "Update available — <v>").
  - If an update is available: **Update** button (running existing server/app update flow).
  - Result line in words ("You're up to date.", "An update is ready.", "Checking for updates…", or "No check yet. Press "Check now".") with "Last checked <date>" and the **Check now** button.
  - Footnote: "Every update is checked before it installs, and rolls itself back if anything goes wrong."

## Servers

- **Active server**: "The server you are using right now, and whether you are
  connected to it." Rows: the server (name and address, "In use: <name>"),
  Connection (state in words, with Connect, Reconnect, Disconnect and Test
  connection), Secure connection (Encrypted / Connecting… / Off in this app) and
  Archangel on your server (version and Running / Can't be reached).
- **Servers**: "The servers saved on this device. Switch between them or add
  another." One row per server: name, address (and computer name for the active
  one), "In use" chip or **Switch to it**, and a menu with Rename and Remove.
  **Add a server** in the header.

## Devices (paired only)

"Phones and computers that are allowed to reach your server." Rows, refresh,
**Add a device** (QR), per-device **Remove** with the existing confirmations,
and the footnote "Only devices listed here can reach your server. Removing one
cuts it off straight away." Loading, error (Retry) and empty states unchanged.

## Admin mode (paired only)

One card: title and switch, the line "Lets the app and the terminal make bigger
changes on your server.", the status chip and the two explaining paragraphs.
Turning it off asks first.

## Security

One card, "Security", with the line "The key and the secure connection that keep
your server private." Three groups:

- **Your key**: SSH key (Manage menu: Change passphrase, Replace key, Forget
  key; or **Add a key**).
- **Connection**: Secure connection (state in words, private address, Encrypted
  or Not connected chip, Connect / Disconnect, Details) and, on a Mac without
  the helper, Allow seamless connection.
- **Repairs** (paired only): Repair server permissions.

## Appearance

Four cards:

- **Look**: Theme, Accent colour, UI scale.
- **Windows and layout** (only when the screen allows Desktop mode, by screen
  width): Layout, Window mode.
- **Desktop** (only in Desktop mode): wallpaper, dock position and size, hide
  the dock automatically, health widget, wallpaper wordmark, and **Customize**.
- **Start-up animation**: Replay first launch, Replay later launch.

## System

- **This device**: "Tidy up the app on this device. Your server is not
  changed."
  - **Free up space**: clears saved image previews and Archangel's own
    temporary folder only. Button "Clear now".
  - **Reset app settings**: asks first.
- **Help & diagnostics**: "Something not working? Send us the details and we
  can help."
  - **Diagnostics**: **View report** and **Copy diagnostics for support**. The
    report holds versions, systems, connection state, health and recent errors.
    It is redacted: the token, keys, pairing bundle, SSH key and passphrase, and
    addresses are never in it, and error text is scrubbed too.
  - **Found a bug?** with **Report a problem**, which opens
    `https://github.com/<kGithubRepoSlug>/issues`.
- **Danger zone** (danger border): Restart server (asks first), Forget this
  server, Remove Archangel from this server (type the server name).

## What went away

"System Information", "Active Server Node", "Developer Options & Diagnostics",
the UI scale reset button (Reset app settings covers it), and the raw
WireGuard, daemon and kernel lines on the main surface (now in Technical
details).

## Tests

`test/screens/settings_screen_test.dart` (behaviour, layout, overflow at 340,
390 and 1400 in both themes) and `test/screens/settings_about_test.dart`
(overview, Technical details, no jargon, sentence case, diagnostics redaction).
