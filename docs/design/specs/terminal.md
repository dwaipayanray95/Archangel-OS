# Spec: Terminal ("Pro console")

Status: **signed off** by Ray (21 Oct 2026). Ready to build.

Design reference: the "Terminal + Files (Archangel OS)" Design canvas (boards
"Terminal · …"). It is private to Ray; this spec is the source of truth.

Goal: polish the existing terminal into the Halo "Pro console". Keep
everything `TerminalScreen` / `TerminalSession` can do today. Build only what
is below.

## Engine facts (read before building)

- Sessions are named server-side shells reached over the archangeld websocket
  (`TerminalSession`, `TerminalSessionApi.list/end`). Names: `main`, then
  `shell-2`, `shell-3`… (`nextSessionName`).
- Statuses: `connecting`, `connected`, `closed`, `error`. `reconnect()` exists.
  `noDataTimedOut` turns true 10 s after connecting with no output.
- `pressKey`, `typeText`, `pasteText`, sticky `ctrlLatched`, text size
  (`kTerminalMinFont`..`kTerminalMaxFont`, saved under `terminal_font_size`).
- `AdminModeService.enabled` gives the Admin mode state.
- **Not in the engine** (app-side work, flagged): snippets storage, detecting a
  sudo command that was blocked. No Alt key.

## Layout

The console is always dark (its own palette, as in the prototype `.con`), in
Pearl and Dawn. The app chrome around it follows the theme.

Decide **wide** vs **narrow** with `LayoutBuilder` on the given width:
wide ≥ 640, narrow < 640. Must work at 340 wide inside a Desktop window and
at 390 on phones without overflow.

### Top bar (left to right)

1. **Tabs**, one per open session: live dot + session name (mono) + ×.
   - Dot: green = connected, amber = connecting, grey = closed/error. The dot is
     decoration; the footer carries the status text.
   - Selected tab gets the raised background.
   - × tooltip/semantics: "End session <name>". Narrow: × shows only on the
     selected tab.
2. **+** icon button, tooltip "New session" (travels directly after the tabs). Opens the next free name.
3. Wide only: `ray@<server>` (mono, muted).
4. Wide only: **Admin key button** (key icon, tooltip "Admin mode", toggles on/off).
5. Wide only: **Snippets** toggle ("Snippets", pressed when the panel is open).
6. **⋯** ("More") menu, always shown.

### More menu

- Row "Text size" with A− · current size (mono) · A+ (live updates text size)
- Snippets (narrow only; wide has the toggle button in the bar)
- Copy selection
- Paste
- divider
- Sessions on this server (opens the existing `SessionsDialog`)

### Ending a session (× on a tab)

× asks first, then really ends the shell on the server:
`confirmEndSession` (danger), wording changes to:

- title: `End session "<name>"?`
- body: "This stops everything running in this session, and anything not saved
  is lost."
- buttons: "Cancel", "End session"

On confirm: `TerminalSessionApi.end`, then remove the tab. On error show the
server message in a snackbar and keep the tab. Closing the window/app still
only detaches (sessions keep running), as today.

### Admin key button

- Key icon button (`Icons.key`), tooltip "Admin mode".
- Off: muted icon (`kConMuted`).
- On: warning tint (`#FFC66E`), selected state.
- Unknown (`enabled == null`): hidden.
- Pressing toggles Admin mode on/off directly.
- Narrow: lives at the right end of the footer.

### Output

xterm `TerminalView`, IBM Plex Mono, current text size. No fake input line.

### Snippets

- Wide: side panel on the right of the output, 260 wide, toggled by the
  Snippets button. Title "Snippets", text "Tap one to put it on the command
  line. It runs only when you press Enter." List rows: name (Inter) + command
  (mono, accent). Bottom button "+ Save a snippet".
- Narrow / phone: same content in a bottom sheet (solid `surface`, grabber,
  close button "Close").
- Tapping a snippet types the command with `typeText` (no newline) and closes
  the sheet.
- "Save a snippet" opens a dialog: fields "Name" and "Command", buttons
  "Cancel" / "Save". Long-press / right-click a saved snippet → "Delete
  snippet" (no confirm).
- Storage: `LocalKvStore` key `terminal_snippets` (JSON list of
  `{name, command}`), per device. Default list when nothing is saved:
  What's running `docker ps` · How full is the disk `df -h` · Memory in use
  `free -h` · Follow Archangel's log `journalctl -u archangeld -f` · Update the
  server `sudo apt update && sudo apt upgrade` · Busy programs `htop`.

### Phone extra keys

Row under the output (phones only, `TerminalAccessoryBar`), keys 44 tall, scroll
sideways: Snippets (code icon) · Esc · Tab · Ctrl (sticky, pressed look while
latched) · ← · ↑ · ↓ · → · | · ~ · / · -. Tooltips as today.

### Footer

`<status>` · `session "<name>"` · wide: `· running <runningSince>` · spacer ·
wide: "Keeps running on your server when you close the app". Narrow: status,
spacer, Admin chip.

Status text: "Connected" (shield, ok) · "Connecting…" (spinner, warn) ·
"Not connected" (error).

## States

- **Connecting**: overlay on the output: spinner, "Reaching your server…",
  `Opening session "<name>".` After `noDataTimedOut`: text becomes "Still
  waiting. Your server is slow to answer." plus a **Reconnect** button.
- **Disconnected** (`closed` or `error`, no exit code): output dimmed, overlay:
  icon cloud_off, "Disconnected", "Your session is still running on the server.
  Reconnect to pick up where you left off.", primary **Reconnect**
  (`reconnect()`).
- **Session ended** (exit frame): "This session ended", "The shell exited.",
  button **Start a new session** (reuses the name).
- **Blocked by Admin mode**: when Admin mode is off and the output contains
  `sudo: a password is required` or `is not in the sudoers file`, show a banner
  above the bottom of the output (warning tint, role status):
  - title (lock icon): "That command needs Admin mode"
  - body: "Your server blocked it because Admin mode is off. Turn it on in
    Settings › Admin mode, then run the command again."
  - buttons: "Open Admin mode" (goes to Settings › Admin mode), "Dismiss".
  - Show at most once per command; never mix into terminal text.
  - Note: this is text matching, not a server signal.
- **Not paired**: keep the current EmptyState.
- **No session open**: keep current ("No session open", New session, Sessions
  on this server).
- Server `notice` frames: keep the dismissible banner.

## Tests

- Wide (1400×900 Simple): tabs, +, A−/A+, Copy, Paste, Snippets, ⋯ present;
  Admin chip shows "Admin off" when disabled, hidden when unknown.
- Narrow (340 in Desktop window and 390 phone): no overflow; A−/A+, Copy,
  Paste, Snippets live in ⋯; chip in footer; × only on selected tab.
- × → confirm dialog with exact wording; Cancel keeps tab; confirm calls end
  and removes tab; end error keeps tab + snackbar.
- Snippets: panel toggles on wide; sheet on narrow; tap types without newline;
  save adds to list and persists (`tester.runAsync`); defaults when empty.
- Phone key row has the 12 keys; Ctrl shows pressed while latched.
- States: connecting overlay; stalled shows Reconnect; disconnected overlay
  calls `reconnect`; exit shows "This session ended"; blocked banner appears
  for the sudo text only when Admin mode is off, and Dismiss hides it.
- Text size clamps at min/max and persists.

## Left out of v1

- Alt key, split panes, search in output, themes for the console.
- Syncing snippets between devices.
- A real "command blocked" signal from archangeld (v1 matches text).
- Turning Admin mode on from the terminal directly.
