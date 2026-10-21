# Spec: Files

Status: **signed off** by Ray (21 Oct 2026). Ready to build.

Design reference: the "Terminal + Files (Archangel OS)" Design canvas (boards
"Files · …"). It is private to Ray; this spec is the source of truth.

Goal: rebuild Files in the Halo look. Browse, preview, download, upload and
copy a private link. Keep everything `FilesService` does today.

## Engine facts

- `FilesService`: `loadDirectory` (403 → not allowed), `retry`, `rootPath`,
  `showHidden`, `openFilePreview` (text, first 400 lines, `isBinary`,
  `mimeType`, `truncated`), `downloadFileBytes`, `downloadToDisk`.
- `FileEntryModel`: name, path, kind (dir/file/symlink/log), sizeBytes, size,
  mtime, isBroken.
- **Ray adds to the engine** (not there yet): upload endpoint and a private-link
  endpoint. Build the UI against a small interface on `FilesService`
  (`upload(dir, files)` with progress, `privateLink(path)`) and leave them
  stubbed until the endpoints land. If the engine says "not supported",
  hide the buttons.
- App-side (no engine change): sorting, image preview from
  `downloadFileBytes`.

## Layout

Wide/narrow with `LayoutBuilder`: two columns (list + 300-wide preview) at
≥ 720; narrow < 720 (phones and narrow windows).

### Header

- Title "Files", subtitle "Everything here lives on your server, not on
  someone else's cloud." (wide only).
- Right: secondary **Open terminal here** (terminal icon) and primary
  **Upload** (upload icon). Narrow: both become 44 icon buttons with those
  tooltips, Upload in accent.
- "Open terminal here" opens Terminal in the current folder (existing
  `pendingTerminalDir` path).

### Breadcrumb

Mono. First crumb = `rootPath` (e.g. `/home/ray`), then each folder, chevrons
between; the last is bold with `aria-current`. Narrow: collapse leading crumbs
to "…" so it stays one line.

### Toolbar

- Filter field, label "Filter this folder" (search icon). Filters by name,
  case-insensitive, this folder only.
- **Sort** button "Sort: <choice>" with menu: Name (A–Z), Newest, Largest.
  Folders always first. Default Name. Remember per device (`files_sort`).
- Switch "Show hidden files" (narrow label "Hidden") → `toggleShowHidden`.
- Wide right side: count "<n> items · <h> hidden" (caption).

### List

- Wide: header row Name / Size / Modified (sort arrow on the active one).
  Rows 46 tall: tile icon (folder = accent wash; file/image/text = neutral),
  name (ellipsis), size (mono, right; folders "—"), modified (mono, right).
- Narrow: rows 54–60 tall: icon, name, subtitle `"<size> · <date>"`
  (folders: `"Folder · <date>"`), chevron on folders.
- Dates: today → "Today, 09:41"; this year → "18 Oct, 22:10"; older →
  "2 Sep 2025".
- Hidden entries (name starts with ".") show in muted text when shown.
- Tap folder → open it. Tap file → preview. Selected file row gets
  `accentWash`.

### Preview

Wide: card beside the list. Narrow: full screen with a ghost back button
"‹ <folder name>".

- Header: file name (mono, wraps) + close icon ("Close preview", wide only).
- Meta: `"<size> · <modified>"` (wide); narrow a list Size / Modified / Where.
- Body by type:
  - text: dark mono block, first 400 lines; footer "Showing the whole file." or
    "Showing the first 400 lines. Download to see the whole file."
  - image (`mimeType` starts with `image/`): fetch bytes, fit to width,
    semantics "Preview of <name>". Above 20 MB show the "no preview" state.
  - anything else: "There's no preview for this kind of file. Download it to
    open it on this device."
- Buttons: primary **Download**, secondary **Copy private link** (copies,
  snackbar "Link copied. It opens only on your own devices.").

### Upload

Picker (multi-file) → upload into the current folder. Progress card:
"Uploading <n> files to <folder>", bar, current file `"<name> · <done> of
<total>"`, button "Cancel". Done → snackbar "Uploaded <n> files", refresh
folder. Name clash → engine decides; show its message. Errors say what
happened and offer "Try again".

## States

- **Loading**: 4 skeleton rows + chip "Opening folder…".
- **Empty**: folder icon, "This folder is empty", "Nothing has been saved here
  yet."
- **Only hidden**: "Only hidden files here" + button "Show hidden files".
- **No match**: `Nothing matches "<filter>"`, "Try a shorter word. The filter
  only looks in this folder.", button "Clear filter".
- **Error**: error icon, "Couldn't open this folder", server message or "Your
  server didn't answer. Check that it's online, then try again.", primary
  "Retry" (`retry`).
- **Not allowed (403)**: lock icon (warning), "This folder is off limits",
  "Files only shows what's inside <rootPath>, to keep system files safe. Use the
  terminal to look elsewhere.", primary "Back to <rootPath>", secondary "Open
  terminal".
- **Not paired**: keep the current EmptyState.

## Tests

- Wide 1400×900: two columns, Upload + Open terminal here, list header, preview
  card with Download + Copy private link.
- Narrow 340 (Desktop window) and 390 phone: no overflow, icon buttons, crumbs
  collapse, preview full screen with back.
- Sort menu changes order, folders stay first, choice persists.
- Hidden toggle; filter; each empty/no-match/only-hidden state text exact.
- 403 shows not-allowed and the back button loads root; error shows Retry.
- Preview: text truncation footer; image path renders from bytes; binary shows
  no-preview text.
- Upload/link: buttons hidden when the service reports unsupported; progress and
  done snackbar with a fake service.

## Left out of v1

- New folder, Rename, Delete (proposal board; needs engine endpoints).
- Moving/copying files, multi-select, drag-and-drop upload.
- Video/audio playback, PDF preview, editing text files.
- Searching below the current folder.
