# Archangel OS: Halo design

This file holds the decisions every screen follows. If a spec and this file
disagree, the spec wins for that screen.

## Who it's for

People who rent a server but aren't sysadmins. The app should feel calm,
trustworthy and premium. It should never feel like a control panel.

Tagline: **"Your private cloud, guarded 24/7."**

## Look

- **Halo**: frosted glass panels over soft glowing backgrounds. There is one
  system with two themes: **Pearl** (light) and **Dawn** (dark).
  "Auto" follows the device.
- Default accent is Halo: a deep violet in Pearl, a mint teal in Dawn. Other
  accents are a user choice.
- Fonts: **Inter** for the UI, and **IBM Plex Mono** for numbers, server names,
  addresses, paths and the terminal.
- Radii: 10 / 14 / 20 / 26, and pill for buttons and chips.
- Cards are glass (`AxCard`, `AxGlass`) with a thin border and no heavy shadows.
  Dialogs and sheets are solid `surface`, so text behind them never shows
  through.
- Logo: only the "Archangel OS" wordmark (`AxWordmark`). No wings, halos,
  angels or other religious imagery, anywhere.
- Motion is subtle and Apple-like. Respect reduced motion.

## Words

- Use plain language and no jargon. Write "secure connection", not
  "WireGuard tunnel", and "apps", not "containers". Mention the technical term
  only as secondary detail, if at all.
- Write in sentence case. Buttons are verbs ("Add a device", "Restart").
- Every risky action says what will happen and asks first (`ConfirmDialog`).
  Irreversible actions make the user type the server name.
- Errors say what happened and what to do next.

## Status

Status is always shown as **icon + text**, never by colour alone.
Use `StatusBadge` and `AxPill`.

| State | Icon | Example text |
|---|---|---|
| OK | `verified_user_outlined` / check | "Connected", "Up to date", "Healthy" |
| Warning | warning | "Needs attention", "Getting full" |
| Error | error / cloud_off | "Not connected", "Your server isn't answering" |
| Info / busy | spinner / info | "Updating…", "Reaching your server…" |

## Layouts

- **Phones** (< 720 wide) use a bottom bar with Home, Apps, Files, Terminal and More.
  More holds Activity, Services and Settings. Screens go one column wide.
- **Tablets and Macs** use **Desktop mode** by default: a wallpaper, a top bar,
  free windows, a dock, a launcher and a health widget. It's customisable:
  wallpaper, dock position and size, auto-hide, pinned apps and the widget. The
  **Simple** layout (glass sidebar, one screen at a time) is the alternative.
- Every screen must look right in all three: phone, Simple, and a Desktop
  window as small as 340×260. Use the width the screen is actually given
  (`LayoutBuilder`), not the screen size. Switch to two columns at about 720.

## Start-up animation

The wordmark appears through an abstract light animation. Tablets and Macs
play the long version (7 s) on every launch. Phones play it on the first
launch and a short 2 s version afterwards. The finished wordmark stays for at
least 3 s, then fades.

## Screen status

| Screen | Prototype | App |
|---|---|---|
| Shell, Desktop mode, boot | signed off | built |
| Home | signed off | built |
| Apps, Run an app | signed off | built |
| Settings | signed off | built |
| Terminal ("Pro console") | signed off | built |
| Files | signed off | built |
| Activity | signed off | to build: `specs/activity.md` |
| Services | signed off | to build: `specs/services.md` |
| Setup wizard | partly | partly |
