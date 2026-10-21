# Spec: Activity

Status: **signed off** by Ray (21 Oct 2026). Ready to build.

Design reference: the Design canvas, page "Activity + Services" (private to
Ray). This spec is the source of truth.

Goal: answer "how hard is my server working right now?" for beginners. Rebuild
`monitoring_screen.dart` in the Halo look, under `lib/ui/screens/activity/`.

## Engine facts

- `MonitoringService`: `status` (disconnected / connecting / connected / error),
  `metrics` (`SystemMetrics`), `processes` (busiest, from the server),
  `totalProcesses`, `error`, `killProcess(pid, force:)`,
  `reniceProcess(pid, priority)`, `setActive`.
- `SystemMetrics`: `cpu` (usagePercent, cores, history), `memory` (used, total,
  usagePercent, history), `disk` (used, total, usagePercent, read/write per sec,
  history), `network` (rx/tx per sec, history), `host` (hostname, os, kernel,
  arch), `uptimeSeconds`.
- Not in the engine: a calm/busy signal (computed in the app, below), a
  "needed by the system" flag, history beyond the live window, search over all
  processes. `rebootHost` exists but is **not** in v1.

## Layout

Use `LayoutBuilder` on the given width.

- **Wide (≥ 720)**: Desktop mode windows, Simple layout content area, tablets.
  Header, status card, four charts in a row (2×2 between 720 and 960), server
  info card, busiest-programs table.
- **Compact (< 720)**: phones and narrow windows (down to 340). Header, status
  card, one card with a row per measure (name · meaning · value), server info,
  busiest programs as rows. Tapping a measure row expands its chart under it
  (one open at a time).

### Header

Title "Activity". Subtitle "Live from <hostname>. Updates every 2 seconds."
(compact: "Live from <hostname>"). Wide: chip "Live" (ok) on the right while
connected.

### Status card

Icon + sentence + one line. Uses the average of the last 10 s of CPU and memory.

| State | When | Icon / tone | Title | Line |
|---|---|---|---|---|
| calm | CPU < 60 and memory < 75 | shield-check, ok | Your server is calm | Everything is running comfortably. Nothing needs your attention. |
| busy | otherwise | pulse, warning | Your server is busy | It's working hard right now. That's fine for a while. If it stays busy, check the programs below. |
| struggling | CPU ≥ 90 or memory ≥ 95 | error, danger | Your server is struggling | It's close to its limits, so things may feel slow. The busiest programs are below. |

### Measures

Values in IBM Plex Mono. Meaning = icon + text, never colour alone.

| Measure | Value | Sub-line (wide) | Meaning |
|---|---|---|---|
| CPU | `12%` | `<n> cores` | < 50 "Plenty free" (ok) · 50–85 "Working hard" (warn) · ≥ 85 "Maxed out" (error) |
| Memory | `2.1 GB` | `of 4 GB · 53%` | < 75 "Comfortable" · 75–95 "Running low" (warn) · ≥ 95 "Almost full" (error) |
| Disk | `78 GB` (wide) / `78%` (compact) | `of 100 GB · 78% · reading 1.2 MB/s` | < 70 "Plenty of space" · 70–90 "Getting full" (warn) · ≥ 90 "Almost full" (error) |
| Network | `1.4 MB/s` (rx + tx) | `↓ 1.1 MB/s · ↑ 340 KB/s` | < 2 MB/s "Quiet" · else "Normal" (both ok) |

Disk chart plots disk activity (read + write) from `disk.history`. Charts: area +
line in accent, no axes, semantics "<Measure> over the last minute". Respect
reduced motion (no animated redraw).

### Server info

Card with Name (hostname), System (`os · arch`), Up for (`uptimeLong`). Mono
values. Kernel is not shown.

### Busiest programs

- Title "Busiest programs". Search field "Search programs" (filters name and
  user in the list the server sent). Segmented "CPU | Memory" sort (default
  CPU, descending).
- Wide table: Program (mono) · Run by · CPU · Memory · ⋯. Compact rows: name
  (mono), sub-line `"<cpu>% CPU · <mem> · <user>"`, ⋯.
- Footer caption: "Showing the <n> busiest of <total> programs."
- Search with no match: `Nothing matches "<q>"`.
- ⋯ menu ("More for <name>"): **Stop**, **Force stop** (danger text), divider,
  **Change priority…** with caption "Advanced".

### Confirmations

- Stop: title `Stop <name>?`, body "This asks it to close. Whatever it's doing
  stops, and apps that rely on it may stop working until it runs again.",
  buttons Cancel / **Stop** (primary). Calls `killProcess(pid)`.
- Force stop: title `Force stop <name>?`, body "Use this only if Stop didn't
  work. It ends the program at once, so anything it hadn't saved is lost.",
  Cancel / **Force stop** (danger). Calls `killProcess(pid, force: true)`.
- Change priority: title "Change priority", body "Lower priority lets other
  programs go first when the server is busy. Most people never need this.",
  segmented Lower (10) / Normal (0) / Higher (-5), note with lock icon "Higher
  needs Admin mode." (Higher disabled when Admin mode is off), Cancel /
  **Apply** → `reniceProcess`.
- Results: success snackbar "<name> stopped" / "Priority changed"; failure shows
  the service message.

## States

- **Connecting** (no metrics yet, status connecting): spinner, "Reaching your
  server…", "Live numbers appear in a moment."
- **Not answering** (status error/disconnected after having tried): cloud-off
  icon (danger), "Your server isn't answering", "It may be restarting or
  offline. We'll keep trying every few seconds.", primary "Try now".
- **No data yet** (connected, history empty): info icon, "Waiting for the first
  reading", "Connected. Charts fill in over the next minute. Numbers show "—"
  until then."
- **Not paired**: keep the current EmptyState.
- Pause polling when the screen is hidden (`setActive(false)`), as today.

## Tests

- Status sentence for calm / busy / struggling at the threshold edges.
- Each meaning label at its thresholds; meanings always have icon + text.
- Wide at 1400×900 shows 4 charts + table; compact at 390 and 340 shows rows,
  no overflow; tapping a row expands its chart.
- Search filters; sort toggles CPU/Memory; footer count text.
- Stop / Force stop / Change priority dialogs: exact wording; Cancel does
  nothing; confirm calls the service with the right arguments; Higher disabled
  when Admin mode is off.
- Connecting, not answering (Try now reconnects), no-data states.

## Left out of v1

- Restart the server (`rebootHost`).
- Per-disk, per-interface and per-core detail.
- History longer than the live window.
- "Needed by the system" markers on programs.
- Searching programs beyond the list the server sends.
