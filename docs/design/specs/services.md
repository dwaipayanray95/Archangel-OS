# Spec: Services

Status: **signed off** by Ray (21 Oct 2026). Ready to build.

Design reference: the Design canvas, page "Activity + Services" (private to
Ray). This spec is the source of truth.

Goal: explain background helpers without jargon. Rebuild `devops_screen.dart`
in the Halo look, under `lib/ui/screens/services/`.

## Engine facts

- `DevopsService`: `services`, `scheduled`, `proxy`, `deployments` (all
  `DevRowModel`: name, meta, status, ok, actions), `loading`, `hasLoaded`,
  `error`, `fetchAll`, `triggerServiceAction(name, Start|Stop|Restart)`,
  `triggerScheduled(name)`, `testProxy(domain)` (returns a message or null),
  `getDeploymentContent(name)`, `deleteDeployment(name)`, `setActive`.
- **Allowed engine change (only this one):** `fetchAll` currently reports one
  error for all four groups. Add per-group failure flags
  (`servicesFailed`, `scheduledFailed`, `proxyFailed`, `deploymentsFailed`)
  so each tab can show its own error. Keep `error` as it is.
- Not in v1 even though the engine has them: `runDeployment`,
  `saveDeployment`.

## Layout

- Header: title "Services", subtitle "The helpers that keep your server running
  in the background." (compact: subtitle only on the first screen). Wide:
  secondary "Refresh" button (→ `fetchAll`). Compact: pull to refresh.
- **Tabs** (pill tabs, scroll sideways when narrow), each with a mono count:
  Background · Scheduled · Web addresses · Deployments. Remember the last tab
  for the session.
- Under the tabs, the group's one-sentence intro (wide: inside the card header
  with a tile icon; compact: plain text above the card):
  - Background: "Programs that run all the time to keep things working, like
    your web server or database."
  - Scheduled: "Jobs that run by themselves at set times, like nightly
    backups."
  - Web addresses: "The web addresses that point to your apps, and the secure
    (HTTPS) setup behind them."
  - Deployments: "Saved setups that describe how an app is installed. You can
    look inside one or remove it."
- Rows: name (mono), meta (muted), status badge (icon + text), actions.
  Wide (≥ 720): one line, actions on the right, wrap below when tight (reuse
  `AxListTile`). Compact (< 720, phones and windows down to 340): name + badge
  on line 1, meta on line 2, actions on line 3.

### Status badge

- `ok == true` → ok, check icon, text = server `status` (e.g. "Running", "Last
  run OK", "HTTPS on").
- `ok == false` and status contains "fail" or "error" (case-insensitive) →
  danger, error icon, server text (e.g. "Failed").
- otherwise → neutral, stop icon, server text (e.g. "Stopped").

### Actions per group

- **Background**: running → ghost "Restart" + "Stop"; not running → primary
  "Start". Only show actions listed in `row.actions`. Busy row shows a spinner
  in the pressed button and disables the others.
- **Scheduled**: "Run now" → `triggerScheduled`; while running the button reads
  "Running…" (spinner). Snackbar "<name> started" or the error.
- **Web addresses**: "Test" → `testProxy(domain)`. Show the result inline under
  the row (role status): success "Works. The address answered with a secure
  connection." (ok); failure "Didn't work: <message>" (danger). Button then
  reads "Test again".
- **Deployments**: "View" opens the content read-only (wide: dialog; compact:
  full-height sheet) with the name (mono), "Read only", the content in a dark
  mono block, buttons "Copy" and close. "Remove" → confirm below.

### Confirmations

- Stop service: `Stop <name>?` / "Anything that needs it stops working until
  you start it again." / Cancel, **Stop** (danger).
- Restart service: `Restart <name>?` / "It goes offline for a few seconds, then
  comes back on its own." / Cancel, **Restart** (primary).
- Start needs no confirmation.
- Remove deployment: `Remove <name>?` / "This deletes the saved setup from your
  server. It can't be undone. Type <name> to confirm." / text field, Cancel,
  **Remove** (danger, enabled only when the typed text equals the name).

## States (per tab)

- Loading (first load): 4 skeleton rows.
- Empty:
  - Background "No background services found."
  - Scheduled "No scheduled tasks yet."
  - Web addresses "No web addresses yet. Make an app public in Apps to get one."
  - Deployments "No saved deployments."
- Error (that group failed): error icon, `Couldn't load <group name lower
  case>`, "Your server didn't answer. Check that it's online, then try again.",
  primary "Retry" (→ `fetchAll`).
- Not paired: keep the current EmptyState.

## Tests

- Tabs show counts; switching keeps state; intro text exact per tab.
- Badge mapping for ok / failed / stopped.
- Background actions follow `row.actions`; Stop and Restart confirm with exact
  wording; Start doesn't.
- Run now shows "Running…" then a snackbar.
- Test shows success and failure messages inline; button becomes "Test again".
- View shows content read-only; Remove needs the typed name.
- Per-group error shows only on the failed tab (fake service); empty and
  loading states per tab.
- 1400×900 wide, 390 phone and 340 window: no overflow.

## Left out of v1

- Run a deployment again, create or edit a deployment.
- Clear stopped-vs-failed from the server (v1 reads the status text).
- Last-run time and output for scheduled tasks.
- Adding or editing web addresses, scheduled tasks or services.
