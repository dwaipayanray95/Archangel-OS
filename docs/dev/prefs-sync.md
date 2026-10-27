# Preference sync

How a person's settings follow them between their Mac and their phone, so a
fresh install skins itself the moment it pairs. Engine design, not a screen
spec: it covers the archangeld endpoint, the client service and the rules that
decide who wins.

Phase 2 of the plan from 27 Oct 2026 (phase 1 was the Browser screen).

## Decisions already taken

- **Appearance follows the active server.** Prefs live on the server, per
  `ServerProfile`. Switching the active server re-skins the app. A local
  "Don't take appearance from my server" switch is the escape hatch.
- **Not everything syncs.** See Scopes.
- **Wallpapers are a path into server storage** (`FilesService`), not an
  uploaded blob. The pref holds a path; the image is fetched and cached by
  content hash. Phase 2b.
- **Per-key revisions, never a whole-document write.** See Conflicts.

## Scopes

Every pref declares one:

| Scope | Syncs | Examples |
|---|---|---|
| `cloud` | everywhere | theme mode, accent, startup sound, wallpaper path, bookmarks, history, which screens were open |
| `deviceClass` | between devices of the same shape (`desktop`, `phone`) | layout (Simple/Desktop), dock position and size, auto-hide, pinned apps, the health widget |
| `device` | never leaves the machine | window geometry, UI scale, full-screen state, hotkeys, the paired host and token |

Two rules follow from this and are easy to get wrong:

- **Window geometry is not a session.** "Restore my last windows" syncs *which
  screens were open and their order* (`cloud`), never pixel rectangles. A phone
  reopens the same screens laid out natively.
- **The token never syncs.** It is the thing that authenticates the sync.

## The endpoint (archangeld — Ray's side, not built yet)

Auth is the existing `X-Archangel-Token` header. Base `/api/v1/prefs`.

### `GET /api/v1/prefs?since=<rev>`

`since` is optional; omit it for everything.

```json
{
  "server_rev": 412,
  "entries": {
    "appearance_accent": {
      "value": "ember",
      "scope": "cloud",
      "rev": 409,
      "updated_at": "2026-10-27T18:02:11Z",
      "device": "mac-1"
    }
  },
  "deleted": [ { "key": "old_key", "rev": 411 } ]
}
```

- `value` is always a **string** — the client owns the encoding, exactly as
  `LocalKvStore` does today. The server never parses a pref.
- `scope` is stored and echoed but **not interpreted** by the server. It exists
  so a second device knows whether a key it has never seen should apply.
  `device`-scope keys are never sent to the server at all.
- `deleted` carries tombstones, with the rev at which the key died. Without
  them a removed bookmark comes back forever.

### `PATCH /api/v1/prefs`

```json
{
  "base_rev": 408,
  "device": "mac-1",
  "device_class": "desktop",
  "entries": { "appearance_accent": { "value": "ember", "scope": "cloud" } },
  "deleted": ["old_key"]
}
```

Response:

```json
{ "server_rev": 412, "applied": ["appearance_accent"], "rejected": {} }
```

- The server bumps one monotonic counter per account and stamps every written
  key with the new rev and its own clock.
- A key whose stored `rev` is **newer than `base_rev`** is a conflict: the
  server keeps the winner by the rule below and returns the winning entry under
  `rejected`, so the client can correct itself in the same round trip.
- `413` when a body or a single value is too large. Cap a value at 64 KiB and
  the whole store at 2 MiB, and say so in the error, because history and
  bookmarks will grow into this.

### `DELETE /api/v1/prefs`

Clears the account's prefs and returns the new `server_rev`. For "stop syncing
and forget what you have of mine" — which the Settings screen must offer, since
this is the user's own server and they should be able to empty it.

## Conflicts

Per **key**, never per document, so two devices changing different settings
never clobber each other.

- The winner is the larger `updated_at`; ties break on `device` id string
  comparison, purely so both sides reach the same answer.
- `updated_at` is the **server's** clock at receipt, not the device's. Phones
  have wrong clocks; the only clock both devices share is the server's.
- A client that loses a conflict adopts the server's value and notifies, even
  if the user set it two seconds ago. Surprising once, consistent always.

## Client (app side)

`lib/services/prefs_sync_service.dart`:

- Registry of known prefs: key → scope. A key not in the registry is never
  pushed, so nothing leaks by accident.
- `LocalKvStore` stays the source of truth for reads. **Nothing blocks on the
  network**: the UI renders local values at launch and sync lands after.
- State: `prefs_synced_rev`, a dirty key set, a tombstone set, and
  `prefs_device_id` (generated once, random).
- On a write: store locally, mark dirty, notify, debounce ~2 s, then `PATCH`.
- On reconnect, and every ~5 minutes while reachable: `GET ?since=<rev>`, apply
  what is newer, then `PATCH` what is dirty.
- Offline: writes queue. The queue survives restart because it is in
  `LocalKvStore` with everything else.
- **Degrade quietly.** A `404` means the server predates this feature: fall back
  to local-only and show "This server can't sync settings yet" in Settings
  once, never an error. Phase 2a ships with the endpoint absent, so this is the
  normal path at first, not an edge case.

### First sync

- Server empty, local customised → push local.
- Server populated, local at defaults → adopt the server's.
- Both populated → the conflict rule decides, per key.
- This needs telling "never touched" apart from "deliberately set to the
  default value", which `LocalKvStore` cannot express today. So on write, record
  the key in a `prefs_explicit` set; keys not in it are defaults and lose to any
  server value regardless of timestamps.

### Multi-server

Prefs are namespaced by `ServerProfile.serverKey` locally, so two servers do not
share a cache. Switching the active server applies that server's `cloud` and
`deviceClass` keys; `device` keys never change. Honour the local "don't take
appearance from my server" switch before applying anything visual.

## Security

- Prefs are **not** encrypted. They sit on the user's own VPS behind the tunnel,
  readable by anyone with the token or root, so nothing sensitive goes in:
  no cookies (decided — no cookie sync in v1), no credentials, no SSH key.
- **Browsing history is the sharp edge.** It is ordinary prefs data by shape but
  not by sensitivity. Before history syncs (phase 2c), decide whether the blob
  is encrypted client-side with the `credential_crypto.dart` passphrase key.
  Leaving it plaintext means a leaked token exposes browsing history. Ray's
  call, and it is a real one.
- One shared token per server means prefs are per-**server**, not per-**person**.
  Key the server's storage `(account_id, key)` with `account_id = "default"`
  from day one, so multi-user later is not a migration.

## Phasing

- **2a** — the sync engine: endpoint contract, `PrefsSyncService`, the scope
  registry, per-key revisions, the offline queue, graceful `404` degradation,
  appearance keys (theme mode, accent, startup sound) migrated onto it, and a
  "Settings sync" line in Settings showing state and last sync. **No server
  endpoint exists yet**, so this ships behind a fake transport in tests and
  local-only at runtime.
- **2b** — wallpaper (as a server storage path, with a picker) and session
  restore (`cloud` open-screens list, `deviceClass` dock/layout).
- **2c** — the browser's bookmarks and history move from `LocalBrowserStore` to
  a syncing store. No screen changes: phase 1 built the seam for this.

## Tests

- Per-key conflict: two devices change different keys offline, both survive.
- Same key both sides: newer `updated_at` wins; the loser adopts it.
- Tombstone: a key deleted on one device stays deleted after the other syncs.
- Defaults never overwrite a server value (`prefs_explicit`).
- `404` → local-only, the Settings line says so, nothing throws.
- Offline writes queue, survive a restart, and push on reconnect.
- `device`-scope keys never appear in a `PATCH` body.
- Switching the active server swaps the applied prefs; the local opt-out stops
  appearance changing.
- All store work inside `tester.runAsync`.
