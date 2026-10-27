# Spec: Browser

Status: **draft, not signed off**. Written from the planning session on
27 Oct 2026. No prototype screen exists yet. Phase 1 builds the mechanics
behind this spec; the look needs Ray's sign-off before it ships.

Goal: a real browser inside Archangel OS. Pages render **on the user's own
device** in a platform webview. The server is not a renderer — it is the
network path, the sync store and (later) the filter.

Architecture decision (locked, 27 Oct): local webview, **not** a server-rendered
pixel stream. Reasons: a 1 GB VPS cannot host headless Chromium alongside the
user's apps; typing latency over the tunnel is unacceptable; no Widevine, so
Netflix and friends show error pages; 1080p30 streaming would become the
server's largest bandwidth consumer. A server-rendered **single tab** stays on
the roadmap as a separate, explicitly-started feature ("remote tab") with its
own spec.

## Phase 1 scope (this spec)

In:

- A `Browser` destination in the shell, working in all three layouts.
- Tabs, omnibox, back / forward / reload / stop, load progress, page title and
  favicon.
- History and bookmarks, stored **locally only** (`LocalKvStore`), capped.
- Find-in-page is out; see "Later".
- Every state: not paired, no page yet, loading, load error, blocked scheme.

Out (later phases, do not build now):

- Preference/history/bookmark **sync** to the server — phase 2. Phase 1 must
  store through a seam that phase 2 can swap for a syncing store without
  touching the screen.
- Cookie sync. Locked decision: **logins are per-device in v1.** Do not read,
  write or transmit cookies.
- "Save to server" downloads, server-compiled blocklists, remote tab.
- Any copy that claims traffic goes through the user's server. The tunnel is
  management-only today (`infra/scripts/wireguard_setup.sh` routes
  `${WG_SUBNET}.1/32` only, with no NAT), so that claim would be false.
  **Decided 27 Oct: phase 1 keeps the split tunnel.** The browser uses the
  device's own internet connection, says nothing about egress either way, and
  shows no routing status. Full-tunnel is a later, opt-in feature.

## Engine facts

- Nothing in `lib/services/` changes. The browser does not touch
  `ArchangeldConnection`, SSH, WireGuard or the registry in phase 1.
- New app-side service only: `lib/services/browser_service.dart`.
- No archangeld endpoints are called in phase 1.

## The webview seam (non-negotiable)

`flutter test` has no webview platform implementation, and neither does Linux
CI. A screen that constructs a plugin webview directly cannot be tested, and
every widget test in the suite that mounts the shell would break.

So:

- `lib/ui/screens/browser/web_view_host.dart` defines an abstract
  `AxWebController` (load, reload, stop, goBack, goForward, canGoBack,
  canGoForward, currentUrl, title, progress, onNavigation, dispose) and an
  `AxWebViewHost` widget that renders a controller.
- `InAppWebController` is the real one, over `flutter_inappwebview` (^6.x —
  the only option that covers **both** macOS and Android and exposes the APIs
  we need; `webview_flutter` has no macOS implementation, and
  `desktop_webview_window` opens a separate OS window, which cannot live inside
  a Desktop-mode `AxGlass` window).
- `FakeWebController` in `test/` drives every widget test. No test mounts a
  real webview.
- The screen talks only to `AxWebController`. If it needs a plugin type, the
  seam is wrong.

## Layout

`LayoutBuilder`, two breakpoints as in `DESIGN.md`: wide ≥ 720, narrow < 720
(phones, and Desktop windows down to 340×260).

### Chrome (top), wide

One row, 44 tall, inside the page's existing `AxPage` padding:

- Back, forward (icon buttons, 44; disabled when the controller says so,
  tooltips "Back" / "Forward").
- Reload — becomes Stop with a close icon while loading ("Reload" / "Stop").
- **Omnibox**: a pill field, mono font (it holds addresses), full remaining
  width. Shows the page's host in normal weight and the rest muted when not
  focused; shows the full URL, all selected, when focused. Placeholder
  "Search, or type an address".
- A bookmark icon button on the right of the omnibox ("Add bookmark" /
  "Remove bookmark", filled star when bookmarked).
- Overflow icon button (`more_horiz`) → menu: History, Bookmarks.

A 2px accent progress line sits under the row while loading, width = progress.
It is removed, not left at 100%, when loading ends.

### Chrome, narrow

Omnibox and reload on one row; back / forward / bookmark / overflow move to a
second row of 44 icon buttons. At 340 wide nothing may overflow — the omnibox
takes whatever is left and ellipsises.

### Tabs

- Wide: a tab strip above the chrome row. Tabs 32 tall, min 120 / max 220
  wide, pill radius, favicon + title (ellipsis) + close icon on hover or when
  selected. Selected tab is `AxGlass`; others are flat with muted text. A "+"
  icon button at the end ("New tab").
- Narrow: no strip. The chrome shows a tab-count pill ("3") that opens a
  full-screen tab list — rows 54 tall with favicon, title, host, close icon —
  plus "New tab" at the bottom.
- Cap at 12 tabs. At the cap "+" is disabled with tooltip "That's as many tabs
  as Archangel OS keeps open."
- Closing the last tab leaves one empty new tab, never an empty strip.
- Tabs other than the selected one keep their controller but must not be
  mounted when the window is narrow (memory on phones). Restoring a tab
  reloads its last URL.

### Page area

Fills the rest. `AxWebViewHost` for the selected tab, with its own clip and the
14 radius of the surrounding card. Nothing is drawn over the page except the
progress line and state views.

## Omnibox behaviour

- Input that parses as a URL with a scheme → load it.
- Input with a dot and no spaces (`example.com`, `192.168.1.1:8080`) → prepend
  `https://` and load.
- Anything else → search. Default engine **DuckDuckGo**
  (`https://duckduckgo.com/?q=<encoded>`), chosen for the privacy story;
  not configurable in phase 1.
- Allowed schemes: `https`, `http`, `about:blank`. Everything else
  (`file:`, `javascript:`, `data:`, app schemes) is refused with the blocked
  state below — this also applies to in-page navigations, not just typing.
- `http://` loads, but the omnibox shows a warning pill "Not secure" (warning
  icon + text, per `DESIGN.md` — never colour alone).

## History and bookmarks

`BrowserService` (a `ChangeNotifier`, `LocalKvStore`-backed, no file IO outside
`tester.runAsync`):

- A visit is recorded on each committed main-frame navigation: url, title,
  host, `visitedAt`. Not recorded: redirects, subframes, reloads of the same
  url within 60 s, or anything loaded while the tab is new/blank.
- History caps at 2000 entries, oldest trimmed. Stored as one JSON string under
  `browser_history`; writes are debounced 2 s so scrolling a site does not
  thrash the file.
- Bookmarks: url, title, `addedAt`, under `browser_bookmarks`. No folders.
- Both go through an abstract `BrowserStore` with a `LocalBrowserStore`
  implementation, so phase 2 can add a syncing one. Keys and JSON shapes are
  phase 2's wire format too — give every record a stable `id` and an
  `updatedAt` now, even though nothing reads them yet.
- **History and bookmarks screens**: full-screen inside the browser (not new
  shell destinations). History groups by Today / Yesterday / date, has a filter
  field, per-row delete, and a "Clear history" action behind `ConfirmDialog`
  ("This removes every page Archangel OS remembers you visiting on this device.
  It can't be undone."). Bookmarks is a plain list with filter and delete.

## States

- **Not paired**: keep the existing `EmptyState` the other screens use.
- **New tab, nothing loaded**: wordmark-free, calm: a globe icon, "Where to?",
  "Type an address, or search. Pages open on this device.", and up to 6
  most-visited chips from history.
- **Loading**: the progress line only. No skeletons over the page — a partly
  painted page is better than a spinner.
- **Load error**: cloud-off icon, "Couldn't open this page", then the specific
  reason where the controller gives one ("That address doesn't exist.", "The
  connection timed out.", "That site's security certificate isn't valid."),
  else "Something went wrong loading that page." Primary **Try again**,
  secondary **Go back** (only when `canGoBack`).
- **Blocked scheme**: lock icon (warning), "Archangel OS won't open that kind
  of link", "It only opens web pages — addresses starting with http or https.",
  primary **Back**.
- **Offline** (no network at all): "You're not connected to the internet",
  "Check your connection, then try again.", primary **Try again**.

## Words

Per `DESIGN.md`: plain language, sentence case, verbs on buttons. Say "pages
open on this device", never "WebView", "WKWebView", "renderer" or "engine". Do
not promise privacy or filtering that phase 1 does not deliver.

## Tests

`test/browser_*_test.dart`, all with `FakeWebController`:

- Wide 1400×900 in the Simple layout: tab strip, chrome row order, omnibox,
  bookmark star, overflow menu entries.
- Narrow 390 (phone) and 340 (Desktop window): no overflow at either; chrome
  wraps to two rows; tab-count pill opens the tab list.
- Omnibox: `example.com` → `https://example.com`; `hello world` → DuckDuckGo
  search; `file:///etc/passwd` → blocked state, nothing loaded; `http://x.com`
  → loads and shows "Not secure".
- Tabs: open, select, close, close-the-last-one leaves one blank tab, cap at 12
  disables "+".
- Back/forward enablement follows the controller; Reload becomes Stop while
  loading and the progress line disappears on completion.
- History: a visit is recorded once, a reload within 60 s is not, the 2000 cap
  trims oldest, Clear history needs the confirm dialog. All store work inside
  `tester.runAsync`.
- Bookmarks: star toggles, survives a fresh `State` (`ValueKey`), appears in the
  bookmarks list.
- Error, blocked, offline and new-tab states: exact text.
- The existing shell tests still pass with the new destination present.

## Later

Find-in-page, downloads ("Save to server" via `FilesService`), server-compiled
content blocking, reader mode, per-tab mute, cookie sync, remote tab, and the
sync of history/bookmarks/open tabs that phase 2 brings.
