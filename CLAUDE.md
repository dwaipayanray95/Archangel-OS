# Archangel OS: notes for Claude

Archangel OS turns a rented VPS into a private cloud for beginners. The Flutter
app is in `app/frontend`. The redesign ("Halo") happens on the branch
`redesign/halo-ui`.

Read `docs/design/DESIGN.md` before you change any UI. Specs for individual
screens are in `docs/design/specs/`. `docs/design/prototype.html` is the
signed-off prototype: open it in a browser to see how a screen should look and
behave.

## How we work

1. A screen is designed in the prototype first and signed off by Ray. Then it
   gets a spec in `docs/design/specs/<screen>.md`.
2. Build only what the spec says. Do not redesign, rename or "improve" things
   on your own. If something in the spec is unclear or can't be done, stop and
   ask.
3. Do one screen per session. Commit when the tests pass.
4. Keep the engine: services in `lib/services/` (SSH, WireGuard, archangeld
   client, crypto, server registry) are not part of the redesign. Do not change
   their behaviour unless the spec says to.

## Commands (run in `app/frontend`)

```sh
dart format -l 140 lib test       # always 140 columns
flutter analyze                   # must say "No issues found!"
flutter test                      # the whole suite must pass
flutter test test/shell_test.dart # one file
flutter run -d macos              # try it
```

Flutter is at `/opt/homebrew/bin/flutter`. v1 targets are macOS and Android.

## Code map

- `lib/ui/theme.dart`: the Halo theme. Use `context.ax` for colors
  (`ax.colors`), spacing (`ax.space`), radii (`ax.radii`) and text
  (`ax.typo`). Never hard-code colors, sizes or fonts.
- `lib/ui/components/`: shared widgets (`AxButton`, `AxCard`, `AxGlass`,
  `AxPill`, `AxListTile`, `AxPage`, `StatusBadge`, `ConfirmDialog`, `HelpTip`,
  state views). Import them all with `lib/ui/ui.dart`. Reuse these before you
  make anything new.
- `lib/ui/shell/`: app shell. Phone bottom bar, sidebar (Simple layout) and
  Desktop mode (`desktop_mode.dart`, `desktop_prefs.dart`,
  `desktop_customize.dart`).
- `lib/screens/` and `lib/ui/screens/<screen>/`: the screens. New screen code
  goes under `lib/ui/screens/<screen>/`.
- `lib/data/app_state.dart`: section, layout, theme, accent.

## Tests: things that bite

- Use `pumpAppShell(tester, layout: ..., desktopPrefs: ...)` from
  `test/test_utils.dart` to test inside the shell. It defaults to the Simple
  layout at 1400×900.
- Widget tests run in a fake-async zone. Real file IO (`LocalKvStore`,
  `ServerRegistry`) must run inside `tester.runAsync`. A save queued outside
  it blocks every later store call and the test hangs.
- After `enterText`, call `pumpAndSettle` before the next tap. The field scrolls
  into view with an animation, and taps during it are ignored.
- Find widgets by `Key`, type or tooltip (`find.byTooltip`), not by semantics
  labels.
- If a test needs a fresh State, give the widget a `ValueKey`.
- Every screen must work at phone width (390), tablet width and inside a
  Desktop-mode window (as narrow as 340). Test the narrow width for overflow.

## Commits

Branch `redesign/halo-ui`. Use a short, plain-English subject that says what
changed for the user. Do not push without Ray's OK.
