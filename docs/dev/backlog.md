# Backlog

What's left after the Halo redesign landed on `main` (review of 2026-10-26).
Ordered by priority inside each group. Tick items off here as they ship.

## A. Bugs and safety fixes (do first)

- [x] **Services: script Run / Edit / New restored** with the admin-mode banner. Kept (Ray, 2026-10-26); spec and intro text updated.
- [ ] *(Later — see F)* **Fullscreen is forced on every launch**, ignoring the saved "Windowed"
      choice (`main.dart` `WindowService.init(fullScreen: true)`, the shell's
      `setFullScreen(true)` after the first frame, and a native toggle in
      `macos/Runner/AppDelegate.swift`). Settings then shows "Windowed" while the
      window is fullscreen. Read the saved preference before init and remove the
      forced calls.
- [x] **Process stop warning restored**; critical processes (PID 1, systemd, sshd, archangeld, WireGuard, Docker) need the name typed.
- [x] **Terminal keeps Alt/Ctrl+Alt+arrows**; snapping needs Cmd+Alt / Ctrl+Alt; skipped in dialogs.
- [ ] *(Kept as is by decision, 2026-10-26)* **UI scale defaults to 80% everywhere**, including Android tablets: body text
      drops to ~11 px and touch targets below 48 dp, and the desktop-mode
      breakpoint is compared against the scaled width. Default to 100% (or floor at
      100% on touch devices) and compare breakpoints against the real width.
- [x] **Window buttons on Windows/Linux windowed mode**; no stacked Quit dialogs.
- [x] **"Restart app" → "Reload interface"**, statics cleared. Follow-up below: it may not actually rebuild.
- [x] ~~"Clear cache" deleted the whole system temp folder (shared `/tmp`).~~ Fixed:
      it now only clears Archangel's own cache.
- [x] ~~Build report committed under `android/build/`.~~ Removed and gitignored.

## B. Needs a decision from Ray

- [ ] *(Backlog — see F)* **System-wide hotkeys** (Option/Alt+Space, Alt+\`, Cmd/Ctrl+Alt+S) work even
      when Archangel is in the background, and clash with Raycast/Spotlight
      alternatives, the Windows window menu and GNOME's window switcher. They're
      never unregistered, and one clash silently disables the rest. Options: keep
      but make them opt-in + configurable in Settings, or drop them. If kept: one
      `try` per hotkey, `show()+restore()+focus()` instead of `maximize()`, and
      unregister on quit.
- [ ] *(Decided: keep the current structure; improve layout and replace jargon with useful info — in progress)* **Settings structure differs from `specs/settings.md`**: the app has About and
      System sections, opens on About, nests Updates and the Danger zone, and shows
      jargon ("WireGuard mesh tunnel", kernel, "Developer Options & Diagnostics").
      Either update the spec to match the app or rebuild Settings to the spec.
- [ ] **Appearance extras not in the spec** (UI scale, window mode, wallpaper
      wordmark switch, inline desktop controls instead of one "Customize" button).
      Keep (and add to the spec) or remove.
- [ ] **Home quick actions** differ from the prototype (prototype: Upload files,
      Back up now, "Restart server"; app: Browse files, See activity, "Reboot
      server").
- [ ] **App catalog** content differs from the prototype list.

## C. Designed but not built yet

- [ ] **Setup wizard in Halo**: the old wizard screen is still used; the pairing-code,
      QR-scan and "Joining your private cloud" screens from the prototype aren't
      built.
- [x] **Files upload** built end to end (server endpoint + multi-file picker, progress, Replace/Skip/Keep both). Was: the button exists but `_handleUpload` sends a dummy
      `upload1.txt` and `supportsUpload` is false. Needs a real multi-file picker
      and a backend upload endpoint (see D). Per spec, hide the buttons when
      unsupported instead of showing a snackbar.
- [ ] **Files "Copy private link"**: hidden (`supportsPrivateLink` false), needs
      backend.
- [ ] **Run an app** is a full page; the prototype is a 3-step modal.
- [ ] **Dock context menu**: add Open / Close window / Keep in dock / Customize dock.
- [ ] **Reduced motion**: only the boot animation respects it. Desktop windows,
      launcher and Activity charts should too.
- [x] **Terminal colours** follow the theme (navy Dawn / pearl Pearl, all ANSI ≥ 4.5:1). Was: spec wants a theme-adaptive console (navy in Dawn,
      pearl in Pearl); the code uses fixed colours. Check ANSI contrast in Pearl.
- [ ] **Sentence case**: "Danger Zone", "Software Updates" → "Danger zone",
      "Software updates".
- [ ] **DESIGN.md housekeeping**: document the keyboard shortcuts, and correct the
      "Screen status" table (Settings and the setup wizard aren't fully per spec).

## D. Needs new backend (Go) work

- [ ] File upload endpoint (with size limits, path jail, atomic writes).
- [ ] Private file links (time-limited, revocable).
- [ ] File new folder / rename / delete (out of v1 per spec).
- [ ] "Back up now" — part of Phase 3 (backups / move to a new server).
- [ ] Metrics history beyond the live window — Phase 3.
- [ ] App catalog / app store endpoint — Phase 4.
- [ ] A real "sudo was blocked" signal from archangeld instead of terminal text matching.

## E. Performance and tidy-up

- [ ] Wrap desktop window contents and the fl_chart charts in `RepaintBoundary`;
      the glass blur (`BackdropFilter`) on top bar/dock is expensive while dragging
      windows on weak GPUs.
- [ ] Remove the unused native `archangel/window` method channel in
      `macos/Runner/MainFlutterWindow.swift` (window_manager does this now) to avoid
      racing the AppDelegate fullscreen toggle.
- [ ] Remove the stale "for now these are the existing screens" comment in
      `lib/ui/shell/destinations.dart`, and fold the thin `lib/screens/*` wrappers
      into `lib/ui/screens/`.
- [ ] Terminal snippets are stored in plain text — add a "don't put passwords in
      snippets" hint.
- [ ] Linux builds now need `libkeybinder-3.0` (hotkey_manager) — document it in
      CONTRIBUTING.md (or drop it with the hotkey decision in B).
- [ ] Clean up the 8 analyzer suggestions (`use_null_aware_elements`).

## Done in this round

- Merged `redesign/halo-ui` into `main` (459 tests pass, analyzer clean of errors).
- CI and release builds moved to **Flutter 3.47.8** (the redesign's packages need
  Dart ≥ 3.8; releases would have failed to build on 3.29.3).

## F. Later

- [ ] "Reload interface" may not rebuild anything (the app root is a const widget) — make it a real reload (new key on the root) or remove it.
- [x] Formatter: one repo-wide format at 140 columns (set in analysis_options.yaml); CI now checks formatting.
- [x] F11 / Cmd+Ctrl+F no longer toggle fullscreen while typing in the terminal.
- [x] One version for the whole product: `version:` in `app/frontend/pubspec.yaml` is the single source (bump with `scripts/bump_version.sh`). The `VERSION` file and `sync_version.sh` are gone, releases always build the server program and every app, and Settings shows one "Archangel OS 0.8.0 (build 2)" row with one Update button.

- [ ] Fullscreen-first launch and saving window preferences (decide behaviour, then fix the forced fullscreen in A).
- [ ] System-wide hotkeys: opt-in + configurable, safe registration, unregister on quit (see B).
- [ ] Dock right-click menu (Open / Close window / Keep in dock / Customize dock).
- [ ] Reduced motion: when the OS "Reduce motion" setting is on, replace window/launcher/chart animations with simple fades.
- [ ] "Run an app" as the prototype's 3-step pop-up (works today as a full page).

## Phases

- **Phase 3 — Safety net:** backups ("Back up now"), restore, move to a new server, alerts, metrics history.
- **Phase 4 — App Store:** app catalog/store endpoint, one-tap apps, web addresses with HTTPS.
- **Phase 5 — Extras:** full-tunnel VPN + ad-blocking, push-to-deploy, scheduler, file create/rename/delete, private file links.
