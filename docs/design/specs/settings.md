# Spec: Settings

Status: **signed off** by Ray. Ready to build.

Goal: rebuild Settings to match the prototype. Keep everything the current
Settings can do, put it into clear sections, and use the Halo look.

## Structure

The sections, in this order:

| id | Label | Icon |
|---|---|---|
| servers | Servers | dns_outlined |
| devices | Devices | devices_outlined |
| admin | Admin mode | key_outlined |
| security | Security | shield_outlined |
| appearance | Appearance | light_mode_outlined |
| updates | Updates | download_outlined |
| danger | Danger zone | warning_amber_rounded (in danger colour) |

Hide Devices and Admin mode while no server is paired, as the app does today.

### Wide (given width ≥ 720)

- Page title "Settings", with the subtitle "Archangel v<version>".
- Two columns: a **section list** on the left (glass card, 220 wide) and the
  **chosen section** on the right.
- In the list, each row is 42 tall with radius 12, an icon and a label. The
  selected row gets an `accentWash` background, accent text and
  `aria-current`. The Danger zone row uses danger text.
- It opens on Servers.

### Narrow (given width < 720, which includes phones and narrow windows)

- Title "Settings", then the section list as full-width rows with a chevron on
  the right.
- Tapping a row shows that section: a ghost button "‹ All settings", then the
  section name as the title, then its content. Back (system back or the button)
  returns to the list.

Decide wide or narrow with `LayoutBuilder` on the width the screen is given,
because inside a Desktop-mode window it can be narrow on a big screen.

### Rows

Most sections are one glass card holding a list of rows. Each row has:

- a **title** (body, text colour)
- a **subtitle** (caption, muted) below it
- **controls on the right**: a small button, a switch, a segmented control or
  a status chip

If the controls don't fit, they wrap below the text (min text width 200).
Use or extend `AxListTile`. Don't make a new row widget per section.

## Sections

The wording is final. Copy it exactly.

### Servers

Card header: **Servers**, with a small **Add a server** button (`+` icon) on
the right. It does what the current Add a server does.

One row per saved server:
- a tile icon `dns_outlined`
- the name in mono
- a subtitle with the host address (mono)
- on the right: for the active server, a chip "✓ In use" (ok). Otherwise a
  small **Switch to it** button.
- a `⋯` icon button (tooltip "More for <name>") with a menu: **Rename**,
  **Remove**. Keep the current Rename dialog and the Remove confirmation.

If there are no servers: "No servers yet." and the Add button.

### Devices (only when paired)

Card header: **Devices**, with a primary small button **Add a device** (QR
icon). It opens the existing `showAddDeviceDialog`.

One row per device (from `DevicesService`):
- a tile icon (phone or computer, depending on the device type if known)
- the name
- a subtitle with the last-seen or added text the service already gives
- on the right: for this device, the chip "✓ This device" (accent). For others,
  a ghost **Remove** button. It keeps the existing revoke confirmation, but the
  wording changes to: title "Remove <name>?", body "It won't be able to reach
  your server any more.", button "Remove".

Footnote under the list (caption): "Only devices listed here can reach your
server. Removing one cuts it off straight away."

Keep the current loading, error ("Retry") and empty states.

### Admin mode (only when paired)

One card with padding 18:
- a row with the title **Admin mode** and a switch on the right (semantics
  label "Admin mode")
- a chip: on → warning "Administrator commands allowed" (key icon). Off →
  neutral "Administrator commands blocked" (lock icon).
- paragraph 1: "When this is on, the app and the terminal can run administrator
  commands (sudo). You need it to install software or change system settings."
- paragraph 2: "Turn it off if you want a safety net against accidental
  changes. Your apps keep running either way."

Keep the current confirmation when turning it off, and the loading and error
states.

### Security

One card of rows:
1. **SSH key**: "Stored on this device, protected by your passphrase. It never
   leaves this device." Right: a small **Manage** button that opens a menu
   with Change passphrase, Replace key (the existing manage-key dialog) and
   Forget key (the existing confirmation). If no key is saved, the subtitle is
   "No key saved yet." and the button is **Add a key**.
2. **Secure connection**: subtitle "Server address <endpoint, mono>". Right:
   the chip "🔒 Encrypted" (ok) when connected, otherwise "Not connected"
   (error), plus a small **Details** button that opens the existing Connection
   details dialog.
3. **Repair server permissions**: "Fixes Archangel's own files on the server
   if something stops working." Right: a small **Repair** button. It does what
   the current one in This server does.

Left out of v1 (shown in the prototype, but the engine can't do them yet):
the Firewall row, Lock the app, and Rotate tunnel keys. Do not build them.

### Appearance

One card of rows:
1. **Theme**: "Pearl is light, Dawn is dark. Auto follows your device."
   Segmented control: Auto / Pearl / Dawn (the system / light / dark theme mode).
2. **Accent colour**: "The highlight colour." Swatch chips as now, with Halo
   first.
3. **Layout** (only when the given width or the device allows Desktop mode, the
   same rule as now): "Desktop mode (the default) gives you windows and a dock.
   Simple keeps one screen at a time." Segmented: Desktop mode / Simple.
4. **Desktop** (only in Desktop mode): "Wallpaper, dock position and size,
   what's in the dock, the health widget." Right: small **Customize** button.
   It calls `showDesktopCustomize`.
5. **Start-up animation**: "Plays every time on tablets and Macs. On phones,
   the long version plays the first time only." Right: two small buttons,
   **Replay first launch** and **Replay later launch**
   (`AppState.replayBoot`).

Left out of v1: the Reduce motion switch. The app follows the device's own
setting.

### Updates

One card of rows:
1. **Archangel OS app**: "Version <AppVersion.current>". Right: "✓ Up to
   date" (ok), or when newer: info "<version> ready" plus a small primary
   **Download** button (it opens the release URL, as now).
2. **Server program**: "Version <server version>". Right: "✓ Up to date", or
   info "<version> ready" plus a small primary **Update** button (the existing
   server update action). While it updates, show info "⟳ Updating…".

Under the card: a ghost **Check now** button and "Last checked <date>"
(caption). Then the footnote: "Every update is checked before it installs, and
rolls itself back if anything goes wrong."

### Danger zone

A card with a danger-colour border. Its rows:
1. **Restart server**: "Your apps stop for about a minute, then start again."
   Small **Restart** button, with the same confirmation as Home's Reboot
   server.
2. **Forget this server**: "Removes it from this device only. Nothing on the
   server changes." Small danger **Forget** button (the current Unpair
   behaviour and confirmation).
3. **Remove Archangel from this server**: "Uninstalls Archangel and its
   secure connection. Your apps and files stay." Solid danger **Remove**
   button. It opens the existing uninstall dialog, which must ask the user to
   type the server name.

## What goes away

- The long single-column page of cards.
- The separate "This server" card. Its parts move to Security (secure
  connection, repair) and Updates (server program).

## Tests

- Update `test/settings_services_test.dart` and any settings tests to the new
  structure. Keep every behaviour test: switching servers, rename/remove,
  revoke, Admin mode confirmation, passphrase change, unpair, uninstall and
  update.
- Add:
  - wide: the section list shows, clicking Security shows its rows, and
    Servers is chosen by default
  - narrow (390 wide): the list shows, tapping Appearance opens it, and
    "All settings" goes back
  - Devices and Admin mode are hidden when unpaired
  - no overflow at 340 wide (Desktop window), 390 and 1400

## Done when

- `flutter analyze` is clean and `flutter test` passes.
- Ray has checked it against the prototype in Pearl and Dawn, on a phone, in
  Simple and in a Desktop window.
