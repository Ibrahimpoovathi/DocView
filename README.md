# DocView — Local-First Document Reader

A Flutter document reader for Android and iOS: PDF, EPUB, Office documents
(DOCX/XLSX/PPTX), comics and common ebook formats — private by design with
optional user-owned WebDAV sync.

## Status

| Phase | Scope | Status |
|---|---|---|
| 0 | Scaffold, core stack (riverpod/go_router/drift), 3-app reference study | Done |
| 1 | Import + library (covers, recents, collections, tags, continue-reading) | Done |
| 2 | PDF reader (pdfrx: TOC, search, bookmarks, dark/fit modes, progress) | Done |
| 3 | Reflow readers (foliate-js: EPUB/MOBI/AZW3/FB2/TXT, CBZ pager, themes) | Done |
| 4 | Office: DOCX native, XLSX tables, PPTX/DOC/ODT/RTF text-first | Done |
| 5 | Search (in-doc + library FTS5), dictionary popup (offline + online) | Done |
| 6 | Dictionary popup (offline StarDict + online fallback, tap-to-lookup) | Done |
| 7 | WebDAV sync (books + progress + collections, on-demand download) | Done |
| 8 | Annotations: highlights/notes/bookmarks + sync + markdown export | Done |
| 9 | Polish: big-library perf, tablet 2-pane, PDF password, last-synced | Done |

Current build: **1.0.0** (Phases 0–9: shell, library, PDF reader, reflow
readers, office readers, search — in-doc + FTS5 library full-text,
dictionary popup — offline StarDict + online, WebDAV sync — manifest
reconcile, on-demand downloads, annotations — highlights/notes/
bookmarks + sync + markdown export, polish — big-library performance,
tablet 2-pane reading, PDF password prompt, last-synced indicator).
See [STUDY.md](STUDY.md) for the
reference-app analysis that drove architecture decisions and [worklog.md](worklog.md)
for the chronological build log.

## Features (plain language)

### 📚 Your Library
1. Add documents from your device or folders (Android/iOS)
2. Bookshelf with real covers and previews
3. "Continue where you left off" shelf
4. Organize into collections, tags, favourites
5. Sort & filter: recent, unread, author, title, type
6. Search the whole library — including words *inside* documents
7. Delete or export files anytime

### 📄 Reading Files
8. PDFs: zoom, page slider, table of contents, in-doc search, bookmarks,
   night mode, password-protected files
9. eBooks: EPUB, MOBI/AZW3, FB2, TXT, comics (CBZ)
10. Reading experience: font, size, spacing, margins; themes (white, sepia,
    dark, pure black); follows system light/dark automatically
11. Flip pages or scroll; progress saved to the exact word
12. Simple comic pager

### 📊 Office Documents
13. Word: paragraphs, tables, lists, images — selectable and searchable
14. Excel: styled tables with frozen headers, swipe through big sheets
15. PowerPoint & legacy files: slide overviews and readable text views

### 🔍 Dictionary & Search
16. Tap a word → instant meaning, works offline after one-time dictionary download
17. Optional online dictionary/translation

### ☁️ Sync Between Your Devices
18. Your own cloud (WebDAV: Nextcloud, Synology, any personal server)
19. Books stored in your cloud, downloaded on demand
20. Progress, bookmarks, notes & collections sync across devices
21. Sync status badges; works offline, catches up later

### ⚙️ Good Habits Baked In
22. Private by design — everything local unless sync is on; no ads, no tracking
23. Fast with big libraries (hundreds/thousands of documents)
24. Tablet layout: browse the library while reading

## Tech stack

- **Flutter 3.47 / Dart 3.13** (matching `pd` toolchain at `~/flutter`)
- **State:** flutter_riverpod 3 · **Nav:** go_router · **DB:** drift (SQLite, FTS5 in P5)
- **PDF:** pdfrx 2.x (MIT, pdfium) · **Reflow:** foliate-js in flutter_inappwebview
  (6.2.0-beta.3, pinned — see STUDY.md §4 for the AGP build saga)
- **Office:** docx_file_viewer + docx_creator · excel_plus · office_oxide_ffi
- **Sync (P6/P8):** webdav_client_plus 3.0.0 · flutter_secure_storage ·
  **Import:** file_picker

Licensing stance: MIT/Apache only (pdfrx avoids AGPL MuPDF; anx-reader's
MIT line; no GPL engines embedded — ReadEra engine routes documented in STUDY.md §1).

## Build & run

```sh
cd ~/Applications/OpenCode/DocView
~/flutter/bin/flutter pub get
~/flutter/bin/flutter run
```

## Release APK (single artifact, rewritten every update)

- Deliverable: **`releases/DocView.apk`** — arm64-only release build (v1.0.0+10 ≈ 33.4 MB),
  committed to git; regenerated and *overwritten* at the end of every change.
- Command to reproduce: `~/flutter/bin/flutter build apk --release --split-per-abi`,
  then copy `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` → `releases/DocView.apk`.
- Emulator/device testing uses the x86_64 split from the same command
  (`app-x86_64-release.apk`) — never committed.
- Version bumps: pubspec `version` + worklog note each update.

### Test results at current build (1.0.0+10)

Static: `flutter analyze` — 0 issues; `flutter test` — 63/63 pass
(format detection, repository CRUD + soft delete + reflow saveProgress,
import pipeline incl. dedupe-by-sha256, TXT→EPUB converter,
PPTX/ODT/RTF extractors, empty-library widget test, FTS5 metadata/body
search + epub/docx text extraction + findTextHits, dictionary parser +
history + MockClient online lookup, dictzip round-trip + StarDict ifo
parsing + article decoding, sync manifest round-trip + push/pull
restore + position LWW + tombstones + collection/tag merge against an
in-memory fake WebDAV, annotation repository CRUD + remote upsert LWW
(deletion-dominant ties) + annotation sync merge both directions).

AVD battery (install, cold launch, screenshot review, FATAL/ANR logcat scan;
run via `tool/battery_all.sh` → per-AVD `tool/battery_one.sh <avd>`):

| AVD | API | Result |
|---|---|---|
| quick_phone | 36 | ✅ battery DOCX renders (ATD API 35 image never painted WebView — swapped to google_apis) |
| old_phone | 30 | ✅ DOCX renders (reflow EPUB shows the graceful WebView-83 error screen) |
| pixel_7 | 36 | ✅ DOCX renders + resume round-trip; XLSX/PPTX/ODT/RTF verified per-format |
| pixel_tablet | 36 (landscape) | ✅ DOCX renders in the **2-pane shell** (library stays live on the left) |

Search batteries (single-AVD, `DOCVIEW_BATTERY_OPEN` + `DOCVIEW_BATTERY_SEARCH`
defines — bar opens with the term pre-filled and searches automatically):

| Target | Term | Result |
|---|---|---|
| PDF (pdfrx `PdfTextSearcher`) | `Battery` | ✅ count `1/1`, highlight painted |
| EPUB reflow (foliate-js `view.search`) | `ribbons` | ✅ count `1/75`, result list + hit navigation |
| Library FTS5 (`document_fts MATCH` + `bm25`) | `ribbons` (body-only) | ✅ Library · 1 — only the EPUB matching *inside* the body |
| Dictionary offline · PDF | `battery` (seeded StarDict) | ✅ popup with offline article, badge `Offline (Battery Seed)` |
| Dictionary offline · EPUB reflow | `silver` (seeded StarDict) | ✅ popup with offline article |
| Dictionary online fallback · PDF | `battery` (no offline dict yet) | ✅ popup with dictionaryapi.dev entry |

Sync batteries (single-AVD, `DOCVIEW_BATTERY_SYNC` define; host runs
`wsgidav` anonymously on :8080 → `/tmp/opencode/dav`, emulator reaches it
at `10.0.2.2`; script `tool/battery_sync.sh <avd> <push|restore|
notes-push|notes-restore>`):

| Run | Flow | Result |
|---|---|---|
| push | fresh install → seeds imported → account auto-configured from define → boot-sync | ✅ server ends with manifest.json + 8 content-addressed books + cover |
| restore | `pm clear` first (fresh device) → define re-saves account → boot-sync pulls | ✅ library repopulated (metadata + covers), cloud-only docs badged |
| on-demand open | tap a cloud-badged doc | ✅ file downloads from server, reader opens (PPTX slide list) |
| notes-push | `DOCVIEW_BATTERY_NOTE=epub` build: JS-simulated selection → highlight + note + bookmark → sync | ✅ server manifest carries annotations; list sheet renders all kinds |
| notes-restore | notes-push then `pm clear` → boot pulls everything → note flow adds local annotations → sync | ✅ server annotations 3 → 6 → 9 across generations (bidirectional merge) |

Big-library battery (single-AVD, `DOCVIEW_BATTERY_BIGLIB=200` +
`DOCVIEW_BATTERY_OPEN=none`; script `tool/battery_biglib.sh <avd>`):

| Run | Flow | Result |
|---|---|---|
| biglib | fresh install → 208-doc seed (batched imports) → grid capture → 4 fling scrolls | ✅ 0 FATAL / 0 app ANR; skipped-frames confined to the seed-import window, grid + scroll smooth; cold start ≈ 3.0 s |

Battery build (`--dart-define=DOCVIEW_BATTERY=true`, optional
`--dart-define=DOCVIEW_BATTERY_OPEN=<fmt>`, optional
`--dart-define=DOCVIEW_BATTERY_SEARCH=<term>`, optional
`--dart-define=DOCVIEW_BATTERY_DICT=<word>`, optional
`--dart-define=DOCVIEW_BATTERY_SYNC=<url>`, optional
`--dart-define=DOCVIEW_BATTERY_NOTE=epub`, optional
`--dart-define=DOCVIEW_BATTERY_BIGLIB=<n>`; `OPEN=none` imports the
seeds but skips the deep-open for library-only batteries) auto-imports a
bundled `assets/battery/mini.pdf` plus in-memory `battery.epub/txt/docx/
xlsx/pptx/odt/rtf` through the real pipeline (asset → importBytes →
sandbox copy → library row → deep-open reader); the shipped APK never
contains the hook. Page-turn swipe + force-stop/relaunch resume captured
per AVD (`<avd>.png` / `<avd>.turn.png` / `<avd>.resume.png`).

**Phase 5 notes**: In-doc search in every reader — PDF via pdfrx
`PdfTextSearcher` (match rects painted through `pagePaintCallbacks`;
the searcher must be created *after* `onViewerReady`, it subscribes to
`controller.document.events` in its constructor and crashes otherwise);
reflow via the foliate-js `search.js` bridge (`docviewSearch`/
`docviewClearSearch` in `docview.html`, result list + prev/next through
CFI jumps; the `docview.html` error handler filters benign
`ResizeObserver loop` errors that fire when the IME opens); office
readers via a shared `findTextHits` text search (docx keeps its native
search FAB; xlsx scrolls to the row, pptx/odt/rtf jump to slide/
paragraph). Library search now walks document *bodies* via FTS5:
SQLite 3.52.0 (bundled by sqlite3_flutter_libs) provides fts5; schema
v4 adds a `document_fts` virtual table with a backfill migration;
background extraction (`text_extract.dart`: pdf/epub/txt/docx/odt/rtf/
pptx/xlsx; FTS5 tables have no UPSERT — rows are read-preserved then
DELETE+INSERT'd; `f MATCH` fails when `f` is a table alias, use
`document_fts MATCH ?`) runs on app boot and after imports; the query
sanitizer quotes terms, caps at 8 words, and falls back to a metadata
substring LIKE for punctuation-only input. Legacy .doc/.ppt now show a
conversion-guidance stub screen (re-save as .docx/.pptx); the `ppt`
format was added to `DocFormat`/detection.

**Phase 6 notes** (dictionary popup): tap/selection → bottom sheet with
the definition, offline-first. Selection capture per reader — PDF via
pdfrx's built-in `PdfTextSelectionParams` (long-press selects the word;
the viewer context menu gains a "Dictionary" action via
`customizeContextMenuItems`); reflow via a `selectionchange` bridge
hooked on every foliate section document in `docview.html`
(`onReflowSelection`, debounced 350 ms; single-word selections open the
sheet, longer ones are treated as copy-flows); ODT/RTF/PPTX via
`SelectableText.onSelectionChanged`. **DOCX is excluded** —
`docx_file_viewer` exposes no selection callback (fork deferred).
Offline = user-imported StarDict: Settings (drawer stub is now a real
page) imports .ifo/.idx/.dict.dz via file_picker into
`<appSupport>/dicts/<id>/`; the dictzip file is decompressed to a plain
`.dict.flat` in Dart at import time (chunk-wise `gzip.decode` — every
dictzip chunk is a standalone gzip member, and the vendored
`ext/fflate.js` only exports `unzlibSync`, which cannot inflate gzip);
`dictview.html` (new foliate asset, served by BookServer at
`/dicts/...`) parses the .idx and answers lookups in a hidden 1×1
WebView engine (`dict_engine.dart`), so no JS inflate is needed at all.
Online fallback = dictionaryapi.dev (`http` promoted to direct dep),
honours the Settings toggle. Recent lookups are kept in
shared_preferences. **Lesson**: shared_preferences 2.5.x's Android
jnigen path crashes with `NoSuchMethodError` on
`SharedPreferencesApiRegistrar.getAll` — pinned to the classic Pigeon
2.4.28 via `dependency_overrides` (the dep existed since Phase 0 but
was never exercised until now). New foliate assets install via a
version-stamped `installed.marker` (bump `foliateAssetsVersion` when
bundled assets change).

**Phase 7 notes** (WebDAV sync): manifest-based reconcile — the server
holds `DocView/manifest.json` (documents with tombstones, reading
positions, collections/tags + links) plus content-addressed
`books/<sha256>__<origName>` and `covers/<sha256>.jpg`. Sync runs
pull → reconcile → push; identity is `sha256` (uuid is NOT stable across
devices — the timestamp-suffix generator — so remote uuids are adopted
on insert). Metadata LWW via a new nullable `Documents.updatedAt`
(schema v5; null = pre-v5 = oldest); positions LWW via the existing
`ReadingPositions.updatedAt`; **tombstone ties are deletion-dominant**
(Drift stores DateTime at second precision — sub-second LWW is a tie,
and a device must never resurrect its own just-deleted doc from its own
earlier manifest push; that exact bug showed up in tests). Books sync
on demand: pull inserts metadata-only "cloud" rows (`textIndexed=1` +
empty-body FTS row so titles stay searchable); opening one downloads
via the open-gate in `_openDoc` (cloud badge on cards), resets
`textIndexed`, and re-runs the FTS indexer. Client =
`webdav_client_plus` 3.0.0 (maintained fork of the dead `webdav_client`
— same API family, Basic/Digest, updated `xml`); credentials in
`flutter_secure_storage`. Settings gains a WebDAV sync section
(connect & test, sync now, download all, remove); the drawer gains
"Sync now"; auto-sync runs at boot and after imports (silent, failure
→ snackbar). Battery-only: `DOCVIEW_BATTERY_SYNC=<url>` auto-configures
the account; battery seeds are idempotent across boots (they embed zip
timestamps, so sha256 dedupe alone would duplicate them per boot).

**Phase 9 notes** (polish → 1.0.0): **Big-library performance** —
`File(...).existsSync()` ran inside every `DocCard`/list-row build for
the cloud badge (one stat() per card per frame) — replaced by a
`cloudOnly` id set computed once per docs-list emission in the library
state (yielding every 50 docs), passed down through cards/list/shelf;
verified on a 208-doc battery (`battery_biglib.sh`: skipped-frames all
inside the seed-import burst, grid + fling smooth). **Tablet 2-pane** —
the reader routes are wrapped in a `ShellRoute`; at ≥840dp the shell
shows the library live in a fixed left pane beside the reader navigator
(open another book to swap the right pane instantly), below 840dp the
reader is full-screen exactly as before. **PDF password** —
`PdfViewer.file` now gets a `passwordProvider` that shows a modal
password dialog (autofocus, obscure, cancel → `PdfPasswordException`
→ viewer error state); repeated wrong attempts reopen the dialog with
an "Incorrect password" title. **Last synced** — `SyncRunner.run`
persists a success timestamp (`shared_preferences`), Settings shows a
"Last synced: <relative>" line under the account tile (or "Never
synced").

**Phase 8 notes** (annotations): schema v6 adds `Annotations` —
`uuid`, `documentId`, `kind` (highlight/note/bookmark), `anchor` (opaque
JSON: reflow relocator `{"cfi": …}` or PDF char range
`{"page","start","end"}`), `excerpt`, `note`, `color` (fixed 5-color
palette, no free-form picker), `createdAt`, nullable `updatedAt` (sync
LWW) and `deletedAt` (tombstones). **Reflow**: the foliate shell
(docview.html) now serializes the settled DOM selection via
`epubcfi.fromRange` and ships it alongside the text — single-word
selections still open the dictionary, multi-word selections open a
floating action bar (5 color dots → highlight, note icon → note).
Highlights render through foliate's `addAnnotation` + `draw-annotation`
→ `Overlayer.highlight` (CSS colors at .3 opacity, replayed per section
on `create-overlay`); tapping a drawn highlight opens the editor sheet.
**PDF**: the context menu gains Highlight/Add-note; anchors are
`{page, start, end}` char indices into pdfrx's deterministic
`PdfPageText`; a pagePaintCallback repaints rects from `charRects`
(grouped per line), with page text cached lazily (`loadStructuredText`
is async, paint callbacks are sync). **Bookmarks** are an annotation
kind anchored at the current page (PDF app-bar toggle) or reflow
location. **Sync**: manifest v2 carries annotations keyed
uuid + sha256; merge is LWW by `updatedAt` with the same
deletion-dominant tie rule as documents — a device never resurrects its
own just-deleted annotation from its own earlier manifest echo (a bug
the tie tests actually caught: Drift stores DateTime at second
precision but ISO-8601 round-trips keep microseconds, so "same second"
must be floored in tests). **Export**: the annotations list sheet
exports per-document Markdown (excerpts + notes + page refs) via the
file picker. Battery: `DOCVIEW_BATTERY_NOTE=epub` simulates a
multi-word selection in JS (`docviewBatterySelect` — the visible
section's text walker), creates highlight + note + bookmark, syncs, and
captures the annotations list; the battery seed idempotency guard now
matches `battery.%` names too (partial imports could lack `mini.pdf`).

**Phase 4 notes**: DOCX = `docx_file_viewer` native widgets (search/zoom/
selection); XLSX/XLS = `excel_plus` table reader (styled header, sheet
tabs, first 3000 rows); PPTX/ODT/RTF = hand-rolled extractors
(`pptx_text.dart`, `odt_text.dart`, `rtf_text.dart`) with per-slide detail
or scrollable text; DOC/PPT (legacy binary) deferred to a later phase and
show the "not supported yet" stub screen. Readers share
`OfficeReaderState` (color mode cycling + scroll-position persistence via
the `progress` location columns; xlsx also persists the sheet name).

**Android runtime notes**: manifest adds `INTERNET` (loopback BookServer
socket) + `usesCleartextTraffic` (loopback http) and disables Impeller for
this app (`EnableImpeller=false` — compositing of the WebView platform view
under Impeller never painted; pure-Flutter UI was unaffected). foliate-js
assets are vendored under `assets/foliate/ext/` (`vendor/` is excluded by
the Flutter bundler; pubspec lists both asset dirs explicitly).

Integration-test harness (`integration_test/app_test.dart`) remains in place;
execution on emulator still deferred for the host-RAM reason in the worklog.

## Docs

- [STUDY.md](STUDY.md) — ReadEra / anx-reader / Readest architecture & feature study
- [worklog.md](worklog.md) — chronological build log (every session, dated)
