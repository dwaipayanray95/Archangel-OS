# Phase 2 - UI rewrite plan

The working spec for rebuilding the Flutter app's UI layer. Agents implementing
any part of Phase 2 follow this document; deviations get noted here.

Goal: the easiest way for someone who has never used Linux to run their own
server - every screen understandable without jargon, every action reachable on
a phone, nothing fake, nothing dangerous without a clear confirmation.

What stays: everything under `lib/services/` (SSH, WireGuard, API clients,
crypto) - the UI is rebuilt on top of it. No new package dependencies unless
this document is updated first (lockfile churn breaks contributors on other
Flutter versions).

## 1. Information architecture

| Destination | Contains | Phone | Desktop |
|---|---|---|---|
| **Home** | Health summary in plain words, what needs attention, quick actions | bottom bar | rail |
| **Apps** | Containers today (App Store in Phase 4) | bottom bar | rail |
| **Files** | File browser | bottom bar | rail |
| **Terminal** | Persistent sessions | bottom bar | rail |
| **More** (phone) | Activity, Services, Settings, server switcher | bottom bar | - |
| **Activity** | CPU/memory/disk/network charts, processes | via More | rail |
| **Services** | systemd services, timers, web addresses (Caddy), scripts | via More | rail |
| **Settings** | Server, devices, Admin mode, security, appearance, updates, danger zone | via More | rail |

User-facing names (never show the internal ones): Containers → **Apps**,
DevOps → **Services**, Monitoring → **Activity**, Reverse proxy → **Web addresses**,
Deployments → **Scripts**, archangeld → **Archangel server**, tunnel/WireGuard → **Secure connection** (with "WireGuard" in detail text only).

- Phone (< 720 px): `NavigationBar` with 5 destinations; desktop: `NavigationRail`
  (extended ≥ 1100 px) with a server switcher at the top.
- Android back button: pops dialogs/sub-pages, then returns to Home, then exits.
- Only the visible destination polls the server (services expose
  `setActive(bool)`; hidden screens pause polling).

## 2. Design system (`lib/ui/`)

- `ArchangelTheme` as a `ThemeExtension` with light **and** dark palettes plus
  "follow system" (setting persisted). Access via `context.ax` (colors, spacing,
  radii, text styles). Old `AxColors` stays only until every screen is migrated,
  then is deleted.
- Contrast: body/label text ≥ 4.5:1, large text and icons ≥ 3:1, in both
  themes - enforced by a unit test over the token pairs actually used.
- Type scale: min 12 sp for any text, 14 sp body; respects system text scaling
  (no fixed-height containers around text).
- Touch targets ≥ 48×48 dp on touch platforms, ≥ 36 on desktop pointer.
- Status is never color-only: every status shows icon + text.
- Components (all with semantics labels and keyboard focus):
  `AxButton` (primary / secondary / danger / ghost), `AxIconButton` (tooltip
  required), `AxCard`, `AxListTile`, `StatusBadge`, `AxPage` (title, subtitle,
  actions, scrollable body, responsive padding), `EmptyState`, `ErrorState`
  (message + Retry + optional "What does this mean?" help), `LoadingState`
  (turns into an actionable "still waiting" message after 10 s),
  `ConfirmDialog` (title, plain-language consequence, confirm label, optional
  type-to-confirm, danger styling), `SshCredentialsForm` (the one shared form
  for host/user/key/passphrase used by setup, update, sync, uninstall,
  admin-mode), `HelpTip` (ⓘ button → short explanation sheet).
- No hard-coded colors outside the theme files.

## 3. Multiple servers

- `ServerProfile { id, name, host (archangeld host:port), token, wgConfig,
  sshHost, sshUser, appPort, wgPort, createdAt }`, persisted by a
  `ServerRegistry` ChangeNotifier in `LocalKvStore` (list + activeId).
- Migration: an existing single pairing becomes the first profile on launch.
- Switching servers: disconnect the current tunnel, bring up the selected
  profile's tunnel, re-point `ArchangeldConnection`, reset per-server service
  state (monitoring history, file path, terminal tabs).
- One tunnel at a time (mobile OSes only allow one VPN).
- Uninstall/update/sync use the active profile's ports and SSH host, never
  hard-coded 8443/51820.

## 4. Screens

Every screen: real data only; empty, loading, error and offline states;
plain-language copy with `HelpTip`s for unavoidable terms; works at 360 px
wide and 1440 px wide.

- **Welcome / setup wizard**: "Do you have a server?" → *Yes, set it up* /
  *I have a pairing code* / *Not yet - show me how to get one* (links to the
  docs guide per provider). Steps one-per-screen with Back/Next, a "what will
  happen" summary before running, live progress, and on failure: what went
  wrong in plain words, likely fixes, Retry and Back - never a dead end.
  SSH-key help: how to find/create one.
- **Home**: health sentence ("All good" / "Disk / is 94% full"), cards for
  CPU/memory/disk with plain labels, "Needs attention" list (stopped apps,
  failed services, updates), quick actions (Open terminal, Run an app,
  Browse files, Reboot - confirmed).
- **Apps**: list of running/stopped apps with status badges, start/stop/
  restart (stop/restart confirmed), logs, remove (type-to-confirm). "Run an
  app" sheet: image, name, ports with explanation ("Private: only your
  devices" default vs "Public: anyone on the internet" toggle), folders,
  settings (env).
- **Files**: phone layout = name + size row with details on tap; desktop =
  table. Download (saves), preview, open terminal here. (Upload/edit/delete
  come with backend support later in Phase 2.)
- **Terminal**: keep the Phase 1 session model; restyle; accessory key bar.
- **Activity**: live charts, processes (kill confirmed, with explanation;
  "priority" instead of "renice"/"niceness").
- **Services**: services (stop guard messages surfaced), timers ("Run now"),
  web addresses, scripts (run confirmed).
- **Settings**: servers (add/rename/remove/switch), this server (hostname,
  versions, update), devices, Admin mode, security (passphrase, SSH key),
  appearance (theme, accent), danger zone (unpair, uninstall).

## 5. Work breakdown

1. **Foundation** (first, alone): `lib/ui/` design system + theme + tests,
   new responsive shell + navigation + back handling, visibility-driven
   polling hooks, `ServerRegistry` + migration + switching, shared
   `ConfirmDialog` and `SshCredentialsForm`. Existing screens keep working
   inside the new shell.
2. **Screens** (parallel, disjoint files): (a) Welcome + setup wizard,
   (b) Home + Activity, (c) Apps + Files, (d) Services + Terminal restyle,
   (e) Settings + dialogs (update/sync/uninstall/manage key onto the shared
   form).
3. **Cleanup**: delete old widgets/`AxColors`, golden/widget tests per screen
   at phone and desktop sizes, accessibility pass.
4. **Docs**: beginner Getting Started, How it works, per-provider guides.

Each step: implemented by a Sonnet agent, reviewed by the orchestrator,
`flutter analyze` clean and `flutter test` green before merge.

## 6. Notes from step 1 (Foundation)

- Theme mode defaults to **dark** (`kDefaultThemeMode` in `lib/data/app_state.dart`)
  until every screen reads colours from `context.ax`; legacy screens still paint
  with the dark-only `AxColors`. Flip the constant to `ThemeMode.system` in the
  cleanup step. Mode and accent are stored in `AppState` (LocalKvStore keys
  `appearance_theme_mode`, `appearance_accent`).
- `SshCredentialsForm` shows "Load from file" only when given an `onPickKeyFile`
  callback: no file-picker package exists and none may be added without updating
  this document. The existing dialogs have no such button today.
- Service polling: `MonitoringService`, `ContainersService`, `DevopsService` have
  `setActive(bool)` and `reset()`; the shell activates only the visible
  destination's services (Home = all three, monitoring at 5 s; Activity = 1 s).
  Screens keep calling `init`/`start` in `initState`; those respect the flag.
  `FilesService`, `DevicesService`, `AdminModeService` have `reset()` only.
- Server switching: `ServerRegistry` stores profiles; `activateProfile`,
  `pairNewServer`, `switchToServer`, `removeActiveServer` (in
  `lib/services/server_registry.dart`) are the only way pairing flows touch
  `WireGuardController`/`ArchangeldConnection`. The active profile is mirrored
  into the legacy storage keys. The shell resets per-server state when
  `ArchangeldConnection.host` changes.
- Uninstall/update/sync dialogs still use hard-coded 8443/51820 and their own
  SSH forms; moving them to the active profile and `SshCredentialsForm` is part
  of step 2(e).
