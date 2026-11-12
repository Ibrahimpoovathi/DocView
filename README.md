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
| 6 | WebDAV sync (books + progress + notes/collections, on-demand download) | Planned |
| 7 | Polish: big-library perf, tablet 2-pane, notes export, release pipeline | Planned |

Current build: **0.6.0** (Phases 0–5: shell, library, PDF reader, reflow
readers, office readers, search — in-doc + FTS5 library full-text). See [STUDY.md](STUDY.md) for the
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
- **Sync (P6):** webdav_client (redirect-safe fork candidate) · **Import:** file_picker

Licensing stance: MIT/Apache only (pdfrx avoids AGPL MuPDF; anx-reader's
MIT line; no GPL engines embedded — ReadEra engine routes documented in STUDY.md §1).

## Build & run

```sh
cd ~/Applications/OpenCode/DocView
~/flutter/bin/flutter pub get
~/flutter/bin/flutter run
```

## Release APK (single artifact, rewritten every update)

- Deliverable: **`releases/DocView.apk`** — arm64-only release build (v0.6.0+6 ≈ 32.5 MB),
  committed to git; regenerated and *overwritten* at the end of every change.
- Command to reproduce: `~/flutter/bin/flutter build apk --release --split-per-abi`,
  then copy `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` → `releases/DocView.apk`.
- Emulator/device testing uses the x86_64 split from the same command
  (`app-x86_64-release.apk`) — never committed.
- Version bumps: pubspec `version` + worklog note each update.

### Test results at current build (0.6.0+6)

Static: `flutter analyze` — 0 issues; `flutter test` — 33/33 pass
(format detection, repository CRUD + soft delete + reflow saveProgress,
import pipeline incl. dedupe-by-sha256, TXT→EPUB converter,
PPTX/ODT/RTF extractors, empty-library widget test, FTS5 metadata/body
search + epub/docx text extraction + findTextHits).

AVD battery (install, cold launch, screenshot review, FATAL/ANR logcat scan;
run via `tool/battery_all.sh` → per-AVD `tool/battery_one.sh <avd>`):

| AVD | API | Result |
|---|---|---|
| quick_phone | 36 | ✅ battery DOCX renders (ATD API 35 image never painted WebView — swapped to google_apis) |
| old_phone | 30 | ✅ DOCX renders (reflow EPUB shows the graceful WebView-83 error screen) |
| pixel_7 | 36 | ✅ DOCX renders + resume round-trip; XLSX/PPTX/ODT/RTF verified per-format |
| pixel_tablet | 36 (landscape) | ✅ DOCX renders |

Search batteries (single-AVD, `DOCVIEW_BATTERY_OPEN` + `DOCVIEW_BATTERY_SEARCH`
defines — bar opens with the term pre-filled and searches automatically):

| Target | Term | Result |
|---|---|---|
| PDF (pdfrx `PdfTextSearcher`) | `Battery` | ✅ count `1/1`, highlight painted |
| EPUB reflow (foliate-js `view.search`) | `ribbons` | ✅ count `1/75`, result list + hit navigation |
| Library FTS5 (`document_fts MATCH` + `bm25`) | `ribbons` (body-only) | ✅ Library · 1 — only the EPUB matching *inside* the body |

Battery build (`--dart-define=DOCVIEW_BATTERY=true`, optional
`--dart-define=DOCVIEW_BATTERY_OPEN=<fmt>`, optional
`--dart-define=DOCVIEW_BATTERY_SEARCH=<term>`; `OPEN=none` imports the
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
format was added to `DocFormat`/detection. Dictionary popup deferred to
Phase 6.

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
