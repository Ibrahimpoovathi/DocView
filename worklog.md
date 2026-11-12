# DocView Worklog

Strictly chronological log of every work session: phase, what changed,
decisions + why, and open issues. Never backfilled.

---

## 2026-10-21 · Phase 0 — Scaffold, core stack, reference study

**What was done**

- Scaffolded Flutter project (Flutter 3.47.5 / Dart 3.13.4, same toolchain as pd)
  via `flutter create --org com.docview --project-name docview`, Android+iOS.
- Added core stack mirroring pd's proven combo: flutter_riverpod 3.4.3,
  riverpod_annotation 4.0.x + generator, go_router 18, drift 2.31, sqlite3_flutter_libs,
  path_provider, file_picker, flutter_inappwebview, pdfrx, epubx, uuid, intl,
  shared_preferences. Dev: drift_dev, build_runner, riverpod_generator.
  (Rejected riverpod_lint/custom_lint — version conflicts with riverpod 3.4.3, same as pd.)
- Wrote app shell: `lib/app/{app,router}.dart`, `lib/core/theme/app_theme.dart`
  (Material 3, seeded light/dark), placeholder LibraryScreen (empty-state + FAB)
  and ReaderScreen route (`/reader/:docId`). Android label set to "DocView".
- Tests: `test/widget_test.dart` — library empty-state smoke test. analyze clean, test pass.
- Reference study (see STUDY.md): inspected ReadEra APK (org.readera) — decoded
  engine bundles (EraPDF=MuPDF AGPL, EraEPUB=CoolReader GPL covering DOC/DOCX/ODT/
  RTF/CHM via reflow, EraMOBI=libmobi, EraDjVu, EraComic, TiER cloud sync permission);
  cloned anx-reader (Flutter, MIT) and Readest (Tauri, AGPL) into /tmp/opencode for
  architecture verification.

**Decisions**

- D1: Reflow rendering = foliate-js inside flutter_inappwebview — validated by both
  anx-reader and Readest independently; pure-Flutter epub_view declined (stale,
  poor maintenance per Flutter Gems).
- D2: PDF engine = pdfrx (MIT/pdfium), avoiding AGPL MuPDF (ReadEra uses AGPL MuPDF;
  we keep commercial-safe licensing).
- D3: Office = hybrid: DOCX native widgets, XLSX native tables, PPTX/DOC/ODT/RTF
  text-first extraction. ReadEra's route-everything-through-reflow validated as
  fallback.
- D4: Keep anx-reader's convert→EPUB canonicalization as a P3 fallback strategy.
- D5: Sync = WebDAV (user's choice); note anx-reader vendored webdav_client fork for
  3xx redirect fixes — likely to adopt similar patch in P6.

**Build issues encountered & fixed**

- flutter_inappwebview 6.1.5 stable (android 1.1.3) fails against modern AGP:
  `proguard-android.txt` no longer accepted. Fix: pin `flutter_inappwebview
  6.2.0-beta.3` (platform packages version-aligned: android 1.2.0-beta.3) —
  builds clean. Anxcye fork (git dep) or an upstream patch as follow-up if needed.
- riverpod_lint 3.1.x vs riverpod 3.4.3 resolver conflict — dropped lint packages
  (matches pd).

**Verification**

- `flutter analyze` — 0 issues.
- `flutter test` — 1/1 passed (library empty-state).
- `flutter build apk --debug` — built (194 MB debug artifact).

**Release pipeline + rigorous AVD testing (same session, continuation)**

- Removed 194 MB debug APK (GitHub 100 MB constraint); established
  **release workflow**: `flutter build apk --release --split-per-abi` → arm64
  artifact (~23.9 MB) copied to **`releases/DocView.apk`**, committed and
  overwritten each update. Version pinned `0.1.0+1`. Emulators get the x86_64
  split (never committed) since all 4 AVDs are x86_64.
- Added `integration_test` harness (`integration_test/app_test.dart`, Phase 0
  smoke suite) + dev dep via manual pubspec edit (pub add wrongly resolves an
  ancient pub.dev copy; must use `sdk: flutter` source).
- Fixed two build-stack breakages found during testing:
  1. **espresso 3.2.0 namespace conflict** — Flutter's androidTest injection
     *strictly* pins runner/rules 1.2.0 + espresso 3.2.0, which modern AGP
     rejects. Fix: `resolutionStrategy.force(...)` on `*AndroidTest*`
     configurations to test-stack 1.6.x/3.6.1 in `android/app/build.gradle.kts`.
  2. **Host OOM kills of qemu** — Flutter template gradle jvmargs `-Xmx8G` on a
     7.6 GB host OOM-killed the AVD repeatedly. Fix: capped to
     `-Xmx2048m -XX:MaxMetaspaceSize=1024m -XX:ReservedCodeCacheSize=256m`.
- Test battery (scripted, with screenshots):
  - quick_phone (API 35 ATD): install ✅, cold launch **617 ms**, dark-mode
    toggle ✅, rotation ✅, **500-event monkey clean**, cold restart **462 ms**,
    logcat FATAL/ANR scan **empty**; dark + light + rotated screenshots verified.
  - old_phone (API 30): install+launch ✅ (2173 ms cold), screenshot verified.
  - pixel_7 (API 36): ✅ (2349 ms cold).
  - pixel_tablet (API 36, landscape): ✅ (5199 ms cold), layout verified.
- integration_test run on emulator is deferred: Gradle debug build + AVD
  concurrently exceed host RAM even after the gradle cap (verified one qemu
  OOM-kill mid-run). Harness ready to execute on a bigger host or CI. The

**Open issues / next**

- Phase 1: import pipeline (file_picker + SAF/iOS picker), drift schema v1,
  covers via pdfrx page-1, library UI, FTS5 skeleton. Then Phase 2 PDF reader.
- Reviewer: install **`releases/DocView.apk`** (0.1.0+1) to sanity-check shell.

## 2026-10-22 — Phase 1 done (0.2.0+2)

**Import + library shipped.** Design system "Bookish warm" locked: Fraunces
(serif display) + Inter (sans UI) bundled as OFL variable fonts; warm
paper/sepia surfaces, terracotta primary; full light+dark ColorSchemes in
`lib/core/theme/app_theme.dart`, tokens in `lib/core/design/dv.dart`.

Data layer (drift, schema v1, copied conventions from pd):
- Tables: Documents (uuid, format-as-enum, sha256 unique for dedupe, soft
  delete via deletedAt, coverPath, lastOpenedAt), Collections,
  DocumentCollections (n:m), Tags, DocumentTags (n:m).
- `LibraryRepository` (watch filters/sorts, CRUD, soft delete, favourite
  toggle, collections/tags joins), `ImportService` (sha256 dedupe, sandbox
  copy `books/<uuid>/orig.<ext>`, unawaited background enrichment),
  `MetadataService` (PDF page-1 cover render via pdfrx `createImageNF` +
  JPEG encode; EPUB container→OPF title/author/cover; formats from
  `DocFormat` magic-sniffing in `lib/core/format/doc_format.dart`).

UI: premium library screen — AppBar with search toggle, filter chips
(All/Favourites/Recent), continue-reading `ShelfBar`, responsive cover grid
(phones→tablet column math) or list view, sort menu, staggered entrance
animation, shimmer `SkeletonDocCard` loading, EmptyState, FAB import, Tools
drawer; doc options sheet (details edit, collections picker, tags, favourite,
export copy, confirm delete); reader route stub.

Dependencies churn worth recording:
- Replaced `epubx` with hand-rolled OPF parsing — it pinned image ^3 which
  conflicts with pdfrx_engine (needs image 4.x API `ChannelOrder`).
- archive 3.6.1 → 4.5.2 (image 4.12 needs archive 4).
- pdfrx 2.4.5 → 2.9.0 / pdfrx_engine 0.7.4: engine 0.4.4 had a null-safety
  compile error in `pdf_file_cache.dart` under the test VM toolchain.
- file_picker 13.x: `.platform` accessor is gone; static methods now
  (`pickFileAndDirectoryPaths` for multi-select, `saveFile` requires bytes,
  `getDirectoryPath` unchanged).
- sqlite3_flutter_libs 0.6.0+eol → 0.5.42: the eol build does NOT bundle
  libsqlite3.so → first AVD run showed a drift dlopen error screen. 0.5.42
  packages the native libs; verified fixed on AVD.
- riverpod_generator 4.x cannot codegen function providers returning
  drift generics (`Stream<List<Document>>`) — InvalidTypeException; those two
  providers (`libraryDocs`, `continueReading`) are manual `StreamProvider`s,
  the rest remains codegen.
- `AppPaths.initForTest()` test hook (path_provider has no plugin in
  `flutter test`); gradle heap cap unchanged.

Tests: 10/10 (`test/widget_test.dart` empty-library render with overridden
in-memory db, `test/doc_format_test.dart` extension+magic detection,
`test/library_data_test.dart` repository CRUD/soft-delete, import dedupe/
unsupported/bytes). `flutter analyze` 0 issues.

AVD battery (script `avd_check.sh` reworked for serial-targeted adb after
"more than one device" races; pkill footgun noted: never `pkill -f qemu`
with an unbracketed pattern — it kills the invoking shell):
- quick_phone: first run exposed the sqlite dlopen failure (screenshot);
  after sqlite3_flutter_libs pin: clean empty library, warm theme renders.
- old_phone (API 30), pixel_7 (API 36), pixel_tablet (landscape): all clean.
- Releases/DocView.apk refreshed: arm64 0.2.0+2, 29.7 MB.

Next: Phase 2 — PDF reader (pdfrx viewer, TOC, search, fit/dark modes,
progress persistence), then wire reader nav from library cards.

## 2026-11-06 — Phase 2 done (0.3.0+3)

**PDF reader shipped** (pdfrx 2.9.0 / engine 0.7.4):
- **Schema v1→v2**: new `ReadingPositions` table (documentId unique FK,
  pageNumber, fitMode + colorMode textEnums, updatedAt). MigrationStrategy
  `onUpgrade` adds the table for existing installs.
- `ReadingRepository` (`features/reader/data/reading_repository.dart`): ensure()
  seeds the row on first open, savePage/savePrefs upsert via read-then-write
  (table has no PK; drift DoUpdate needs an explicit target — read-then-write
  is simpler and partial-safe). Update writes only provided columns.
- `ReaderScreen` rebuild (`presentation/reader_screen.dart`):
  - boot resolves doc + saved position, marks `openedAt`, then mounts
    `PdfViewer.file` with `initialPageNumber` (no remount guesses)
  - progress save: debounced 600 ms on page change, flushed on dispose +
    `didChangeAppLifecycleState(paused)`
  - bottom bar: outline, search, color-cycle (normal→sepia→dark), page slider
    `n / total`; color modes driven by `PdfViewerParams.pageImageColorFilter`
    (invert matrix for dark, sepia matrix for sepia — page bitmaps only,
    overlays/UI stay clean)
  - in-document search: `PdfTextSearcher` over `PdfViewerController` —
    live match counter `idx/total`, prev/next, reset on close
  - outline sheet: `controller.useDocument((d) => d.loadOutline())`, flattened
    with indent + `goToPage(dest.pageNumber)`; snackbar when empty
  - non-PDF formats show "reflow lands in Phase 3" notice screen (EPUB etc.
    wired properly in Phase 3)
- **Battery hook system**: `--dart-define=DOCVIEW_BATTERY=true` adds a
  `/reader-debug/raw` route + library auto-seed that imports a bundled
  hand-crafted `assets/battery/mini.pdf` (valid 1-page PDF built by script
  during P2 setup) through the REAL pipeline (importBytes → sandbox copy →
  library row) and deep-opens the reader automatically. Shipped APK contains
  none of this. Verified render on all 4 AVDs (quick_phone/old_phone/pixel_7/
  pixel_tablet — incl. portrait and landscape), 0 FATAL exceptions in
  every logcat scan.
- Tests: reading_repository_test (4 cases) + all prior suites → 14/14;
  analyze clean. Note: drift data classes still force manual riverpod
  providers for typed generics (docByIdProvider added the same way).
- Releases/DocView.apk rebuilt: arm64 0.3.0+3 ≈ 30.6 MB.

Next: Phase 3 — reflow readers (foliate-js EPUB/MOBI/AZW3/FB2/TXT + CBZ
pager), reader routing per format, shared reader theming.

## 2026-11-08 — Phase 3 done (0.4.0+4)

**Reflow readers shipped** (foliate-js EPUB/TXT via flutter_inappwebview):
- **Schema v2→v3**: ReadingPositions gains `progress` (0..1 fraction) and
  `location` (CFI) columns; migration `onUpgrade` adds them; existing
  PDF rows keep working and `savePage` leaves them untouched.
- `txt_to_epub.dart`: plain TXT → minimal 3-asset EPUB (container.xml,
  OPF, XHTML chapters, mimetype **stored/uncompressed** — archive 4.5.2
  has no `ArchiveFile.STORED`, use `..compression = CompressionType.none`;
  deterministic output covered by tests). TXT files open through foliate-js
  like any EPUB — one renderer, no bespoke reader.
- `book_server.dart`: loopback shelf server gains `shelf_router`
  (^1.1.5) routing `/foliate/**` (foliate-js assets), `/files/**` (book
  sandbox), `/txt/**` (bash64-decoded text chapter). Router instance is
  `.call`-able, but must not be passed as Handler directly.
- `foliate_assets.dart`: installs the `assets/foliate/**` tree (incl.
  `ext/` vendored zip.js + fflate) into App Support; filters basenames
  starting with `.` (AssetManifest lists `.gitattributes` but it cannot
  be loaded → crash). Flutter's asset bundler is non-recursive and
  **excludes `vendor/` dirs** → vendored deps live in
  `assets/foliate/ext/`, `view.js` rewritten to `./ext/…`, pubspec lists
  both `- assets/foliate/` and `- assets/foliate/ext/` explicitly.
- `docview.html` glue page: params `src/color/frac/loc`; loads the book,
  applies color mode (normal/sepia/dark via body class + meta theme),
  restores `frac`/`loc`, then reports `onReflowReady` + `onReflowProgress`
  (debounced fraction + CFI) to Flutter handlers; errors report
  `onReflowError` with stack, plus a classic-script `error` listener
  tagging `BOOTERR <file>:<line>`. Initial startup uses
  `.then/.catch` (top-level await = SyntaxError on older WebViews).
- `reflow_screen.dart`: WebUri built as
  `p.relative(storedPath, from: AppPaths.booksDir.path)` URL-encoded per
  segment; progress saved debounced 600 ms (fraction + CFI into
  `saveProgress`), flushed on pause/dispose; bottom bar reuses the shared
  `ReaderBottomBar` in `fractionMode` (permille slider → `window.docviewGoToFraction`);
  TOC via `window.docviewToc()` JSON; color cycle re-cycles mode and
  reloads through the (cached) `_bookUrlFuture` so the server stays up;
  `useHybridComposition: true`; opaque surface scrim + PulseLoader while
  booting; graceful `_error` screen on reflow errors (old WebViews land
  here safely, no crash).
- `reader_screen.dart`: when `doc.format != pdf` and format ∈
  `reflowFormats`, auto-dispatch to `ReflowScreen`. MOBI/AZW3/FB2/CBZ are
  still "not supported yet" stubs (P3.5).
- Android manifest: `<uses-permission android:name="android.permission.INTERNET"/>`
  (loopback ServerSocket failed without it — "Operation not permitted"),
  `android:usesCleartextTraffic="true"` (loopback http is treated as
  cleartext), `<meta-data android:name="io.flutter.embedding.android.EnableImpeller"
  android:value="false"/>`.

Key debugging lessons (worth keeping):
1. **Impeller blank WebView**: with Impeller (default in this Flutter),
   the platform view WebView never painted (or painted dark) — the
   status bar even pulsed. Explicit Impeller opt-out in the manifest
   fixes it globally for the app.
2. **Android OEM WebView versions**: quick_phone/old_phone shipped
   WebView 83 → foliate-js's private class methods (`#emit`) hard-fail at
   parse time. Minimum WebView is 84+; old AVDs now show the graceful
   error screen instead. Document in README.
3. **Flutter asset bundler quirks**: non-recursive; silently drops
   `vendor/` paths; hidden dotfiles appear in the manifest but are
   unloadable.
4. **Emulator battery script**: resident **Gradle daemon (-Xmx2g) +
   Kotlin compile daemon (7200s keepalive)** held 3.5–4.5 GB of the
   7.6 GB host for the whole session — qemu died silently whenever the
   host was pressured. New permanent rules, embedded in the
   `tool/battery_one.sh` / `tool/battery_all.sh` scripts: kill both
   daemons immediately after *every* build; boot AVDs with `-memory 2048`;
   never build while an emulator is running; one AVD at a time; bracketed
   pkill patterns only (`[G]radleDaemon`).
5. **quick_phone ATD image never painted WebView content** (even plain
   HTML). Swapped the AVD image to
   `system-images/android-36/google_apis/x86_64` (`tag.id=google_apis`,
   `image.sysdir` update in `config.ini`); WebView now reports a modern
   version and the battery EPUB renders.

Battery: `tool/battery_one.sh <avd>` runs install → cold launch →
screenshot → swipe page-turn screenshot → force-stop → relaunch
(resume screenshot) → logcat dumps → teardown, with the daemon rules
enforced before/after. `tool/battery_all.sh` runs the 4 AVDs serially
and greps FATALs. Results at 0.4.0+4: ALL FATAL-free; pixel_7 +
pixel_tablet + quick_phone render the battery EPUB (Chapter Wind,
progress slider functional, resume round-trip verified); old_phone shows
the graceful WebView-83 error screen by design.

Tests: `test/txt_epub_test.dart` (converter: mimetype position/
compression, OPF structure, chapter split, determinism) + new
`reading_repository` saveProgress case → **17/17**, analyze clean.

Releases/DocView.apk rebuilt: arm64 0.4.0+4 ≈ 31.5 MB (splits also built
for armeabi-v7a/x86_64).

Open for P3.5: MOBI/AZW3/FB2 decode (convert→EPUB per D4) + CBZ pager;
search in reflow docs (P5); battery screenshots sometimes show a
"System UI isn't responding" ANR dialog — host-stress cosmetic only,
app itself FATAL-free.

## 2026-11-09 — Phase 4 done (0.5.0+5)

**Office readers shipped** (DOCX native, XLSX tables, PPTX/ODT/RTF text).

Per user decision: **zero-risk scope** — `office_oxide_ffi` (unverified
publisher, 8 downloads, native-lib build hook) was rejected; legacy
binary .doc/.ppt are deferred to a later phase (they surface the
existing "not supported yet" stub, no FATALs).

Dependencies (after our `xml: ^6.6.1` pin was bumped to `^7.0.1` — the
old cap silently forced pub to resolve ancient package versions):
- `docx_file_viewer` 1.0.5 (MIT/Apache, verified publisher, 6.3k dl)
  — pure-Flutter DOCX widgets, DocxSearchController, zoom, light/dark
  themes. Pulled-in `docx_creator` 1.4.0 (direct dep too: used to
  generate battery DOCX in memory). xml `namespace` → `namespaceUri`
  rename updated our EPUB OPF parsing.
- `excel_plus` 2.29.2 (MIT, verified, 51k dl, SAX + lazy sheets) —
  xlsx reader incl. legacy .xls (BIFF8 read-only), async decode
  (`decodeBytesAsync`), `Data.displayText` for formatted cells,
  `streamRows` available for the future large-sheet path.

Data extractors (hand-rolled, all unit-tested):
- `pptx_text.dart`: slides from `ppt/slides/slideN.xml` `<a:t>` runs,
  sorted by real slide number (zip order irrelevant), first run = title.
- `odt_text.dart`: `content.xml` walk, `text:h`/`text:p` in document
  order (nested list paragraphs preserved).
- `rtf_text.dart`: compact RTF state machine — group/destination skips
  (`{\*\...}`, fonttbl/colortbl/stylesheet/info), `\'hh` cp1252 escapes
  `\ par/line/sect/tab`, `\uN;` with `\uc` fallback-char suppression,
  `\binN` skip. RTF `\uNNNN` is **decimal** (test bug caught by tests).

Screens (`office_screens.dart`, shared `OfficeReaderState` base):
- `DocxScreen`: `DocxViewWithSearch` inside our themed Scaffold; color
  mode → DocxViewTheme.light()/dark() + paper background; position
  restore not exposed by the widget (openedAt still saved).
- `XlsxScreen`: decodeBytesAsync → capped 3000 rows/sheet; sheet
  ChoiceChip tabs; frozen styled header row; `IntrinsicColumnWidth`
  (FlexColumnWidth crushed cells on narrow screens); progress column
  saves scroll fraction and the **sheet name** in `location`.
- `PptxScreen`: slide overview cards → per-slide readable text page.
- `TextDocScreen`: ODT/RTF scrollable selectable text; scroll fraction
  persisted via `saveProgress`.

Dispatch: reader_screen switch — office formats before the
"not supported yet" stub. No schema change: Phase 3's
`progress`/`location` columns carry office scroll positions.

Battery: seed extended with `battery.docx/xlsx/pptx/odt/rtf`
(docx_creator + excel_plus generate them in memory; pptx/odt zipped by
hand); battery runs can pin the auto-open format with
`--dart-define=DOCVIEW_BATTERY_OPEN=<fmt>`. Results: DOCX on all 4 AVDs
(including old_phone API 30 — DOCX is pure Flutter, no WebView);
XLSX (styled table + tabs), PPTX (3-slide overview), ODT (heading +
paragraphs), RTF (é escape, skipped `{\*\generator}`) on pixel_7 —
ALL FATAL-FREE.

Tests: 25/25 (8 new extractor tests). `flutter analyze` 0 issues.
Releases/DocView.apk rebuilt: arm64 0.5.0+5 ≈ 32.5 MB.

Open next: P4.5 legacy .doc/.ppt (needs an engine decision — revisit
office_oxide_ffi maturity or an offline_document_viewer bundled option);
large-sheet lazy rows (streamRows) if real-world workbooks hit the cap;
Phase 5 search (FTS5 + in-doc).

## 2026-11-10 — Phase 5 done (0.6.0+6)

Format-aware stub for legacy .doc/.ppt (P4.5 dropped — usage data says
these formats are dying; .xls already covered by excel_plus): readers
now show conversion guidance ("re-save as .docx/.pptx"). Added the
missing `ppt` entry to `DocFormat` + detection rule.

### In-doc search (every reader)

- PDF (pdfrx 2.9.0 `PdfTextSearcher`): shared `ReaderSearchBar`
  (reader_chrome.dart) + match rects painted via
  `pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback]`.
  **Crash lesson**: the searcher must be created *after* the document
  is ready — its constructor subscribes to
  `controller.document.events` and hits a null check otherwise
  (`_searcher` is now created in `onViewerReady`, battery hook starts
  the search there too). Null-aware list element `[?expr]` keeps
  paint callbacks empty until then.
- Reflow (foliate-js): `window.docviewSearch/docviewClearSearch`
  bridge in docview.html (seq-superseded generator, 800-hit cap,
  excerpt pre/post ±60 chars); Dart side holds hit list + prev/next
  via `docviewGoTo(cfi)` + a result-list bottom sheet; count-tap opens
  it. **Lesson**: opening the IME fires the WebView error handler with
  a benign `ResizeObserver loop` error — the handler now filters it
  (was falsely killing the reader in battery runs).
- Office: shared `_OfficeSearchSheet` over `findTextHits`
  (text_search.dart, case-insensitive, 400-hit cap). xlsx scrolls to
  the matching row fraction, pptx pushes the slide, odt/rtf scroll to
  the paragraph; DOCX keeps its native search FAB.

### Library full-text search (FTS5)

- sqlite3_flutter_libs 0.5.42 bundles SQLite 3.52.0 **with fts5** (the
  emulator's own sqlite3 is irrelevant — verified in tests + battery).
- Schema v4: `document_fts` virtual table + `textIndexed` column +
  backfill migration (onUpgrade <4 / onCreate).
- `text_extract.dart` extracts body text for pdf (pdfrx `loadText()`,
  500-page cap), epub (container→OPF spine walk, HTML stripped),
  txt/docx (new `docx_text.dart` extractor), odt/rtf/pptx/xlsx; 1.5 MB
  cap, all errors swallowed to ''. Non-indexable formats (mobi, cbz,
  legacy office…) record an empty body — metadata still searchable.
- `text_index_repository.dart` runs pending extractions in batches of
  8 on app boot and after each import (reentry-guarded).
- Search path: `ftsMatchQuery` sanitizer (unicode words → quoted
  AND-terms, 8 max) → `document_fts MATCH ? ORDER BY bm25(document_fts)`
  via drift `customSelect`; punctuation-only queries fall back to
  metadata substring. **FTS5 gotchas**: virtual tables don't support
  UPSERT (rows are read-preserved, DELETE+INSERT in a transaction) and
  a table alias can't appear left of `MATCH` or inside `bm25()` —
  write `document_fts MATCH ?` / `bm25(document_fts)`.
- Battery additions: `DOCVIEW_BATTERY_SEARCH=<term>` define,
  `DOCVIEW_BATTERY_OPEN=none` (import seeds, skip deep-open for
  library-search runs), LibraryScreen boot hook (opens search bar,
  preloads term).

Battery: baseline all 4 AVDs FATAL-FREE; EPUB reflow search
(`ribbons` → 1/75 + highlight) and library FTS search (`ribbons`,
body-only term → Library · 1 EPUB card) on pixel_7; PDF search
initially hit host stress (grey screens) but the retry exposed a **real
crash** — the null-document PdfTextSearcher constructor — fixed as
above, then verified `1/1` FATAL-FREE.

Tests: 33/33 (8 new: FTS metadata/body search, soft-delete exclusion,
sanitizer, epub spine + docx paragraph extraction, findTextHits).
`flutter analyze` 0 issues. Releases/DocView.apk rebuilt: arm64
0.6.0+6 ≈ 32.5 MB.

Open next: Phase 6 — dictionary popup (offline + online) or WebDAV
sync; git init still pending (offered every phase).

## 2026-11-12 — Phase 6 done (0.7.0+7)

Phase 6 = dictionary popup (user-approved reordering: WebDAV sync moves
to Phase 7). Scope decided up front: bottom-sheet popup everywhere,
DOCX deferred (no selection callback in docx_file_viewer without a
fork), offline = user-imported StarDict.

### Lookup service + popup

- `dictionary_service.dart`: dictionaryapi.dev parser (phonetic +
  meanings/definitions, tolerant of empty alternates), `OnlineDictionary`
  (8 s timeout, all failures → null), `LookupHistory` in
  shared_preferences (dedup case-insensitive, 30 cap).
- `dictionary_sheet.dart`: bottom sheet (DraggableScrollableSheet,
  Dv tokens) — loading, empty, offline article (pre-wrap + source
  badge), online article (phonetics + POS chips + italic examples);
  history records real hits only.

### Selection capture

- PDF: pdfrx selection is built-in (`PdfTextSelectionParams`); added
  `showContextMenuAutomatically` + `customizeContextMenuItems` with a
  "Dictionary" item (getSelectedText → clearTextSelection → sheet).
- Reflow: `docview.html` hooks `selectionchange` on every section doc
  (attached in the renderer `load` event — foliate swaps iframes per
  section), debounced 350 ms, `onReflowSelection` → single-word
  selections auto-open the sheet.
- ODT/RTF/PPTX: `_DictSelectableText` wrapper over `SelectableText`
  (`onSelectionChanged`; note the Flutter-3.47 callback signature has a
  nullable `SelectionChangedCause`).
- DOCX: excluded (package exposes no hook) — documented limitation.

### Offline StarDict (the spike that mattered)

- Vendored `ext/fflate.js` exports only `unzlibSync` — it cannot
  inflate gzip, so dict.js's DictZip path is unusable in our WebView.
  Solution: decompress `.dict.dz` **in Dart at import time**
  (`dict_zip.dart`: parse the FEXTRA 'RA' chunk table, `gzip.decode`
  each chunk — every chunk is a standalone gzip member; decompressed
  offsets equal the .idx offsets, so the index stays valid).
- `dict_registry.dart`: per-dict dirs under `<appSupport>/dicts/<id>/`
  (`.ifo/.idx/.dict.flat`), registry JSON in shared_preferences,
  import/remove/register; Settings screen (drawer stub → real page)
  imports via file_picker's `pickFileAndDirectoryPaths` and lists/
  removes dictionaries + online-fallback toggle.
- `dictview.html` (new foliate asset): parses .ifo/.idx, lazily loads
  the whole plain `.dict.flat`, binary-searches like foliate's dict.js
  (case-insensitive strcmp + adjacent duplicates), decodes articles per
  `sametypesequence` ('m' plain, 'h'/'x' html-stripped).
- `dict_engine.dart`: hidden 1×1 WebView engine + controller (load
  dedup, request-id completers); the sheet mounts it in a Stack.
- foliate assets now install via a version-stamped `installed.marker`
  (`foliateAssetsVersion = '6'`) so new assets reach existing installs.

### Bugs found by battery (all fixed + verified)

1. **shared_preferences 2.5.x Android jnigen crash** —
   `NoSuchMethodError` on `SharedPreferencesApiRegistrar.getAll`; the
   dep existed since Phase 0 but was never exercised. Pinned
   `shared_preferences_android: 2.4.28` (classic Pigeon channel) via
   `dependency_overrides`.
2. `DictRegistry.register`/`LookupHistory.record` crashed on the
   empty-list `const []` trap (same lesson as the FTS phase — never
   mutate a `recent()`/`list()` return directly).
3. `DictEngine` returned a `Positioned` under an `Align` (not a Stack)
   → applyParentData crash; root is now a plain 1×1 SizedBox.
4. Offline lookups silently fell back to online in the PDF battery:
   foliate assets were never installed outside reflow — the engine now
   calls `installFoliateAssets()` before first load.

Battery: PDF+dict (`battery` → offline hit, badge `Offline (Battery
Seed)`), EPUB+dict (`silver` → offline hit), online-fallback run
(phonetics + definitions from dictionaryapi.dev) — plus the standard
baseline: all 4 AVDs FATAL- and ANR-free.

Tests: 49/49 (16 new: dictionary parser/history/online, dictzip
round-trip incl. a synthetic dictzip builder, ifo parsing, article
decoding). `flutter analyze` 0 issues. Releases/DocView.apk rebuilt:
arm64 0.7.0+7 ≈ 32.8 MB. Commits handled by the user (approval-gated).

Open next: Phase 7 — WebDAV sync (settings + credential storage,
upload/download of books, delta-sync of documents/reading positions/
notes, redirect-fork watch for webdav_client), or polish items.

---

## Phase 7 — WebDAV sync (0.8.0+8)

**Decision set (user-approved):** manifest-based reconcile (no migration
to a change-log); skip notes sync (no notes feature exists yet); books
sync on demand only; identity = sha256 (uuid is generated per-device —
`_uuid()` uses a timestamp suffix — so remote uuids are adopted on
insert). `webdav_client` 1.2.2 turned out dead (pins ancient `xml`,
conflicts with our ^7.0.1) → `webdav_client_plus` 3.0.0 (maintained
fork, same API family, Basic/Digest). Credentials in
`flutter_secure_storage` 11.2.0.

**Schema v5**: `Documents.updatedAt` (nullable) for metadata LWW —
nullable so `ALTER TABLE ADD COLUMN` works; null = pre-v5 = oldest.
Repository stamps `updatedAt` on every mutation. Drift stores DateTime
at second precision → ties are real; **tombstone ties are
deletion-dominant** (a device must never resurrect its own just-deleted
doc from its own earlier manifest push — this exact bug showed up in
tests and is the reason ties don't default to local).

**Server layout** (`<base>/DocView/`): `manifest.json` (documents with
tombstones, positions, collections/tags + name links), content-addressed
`books/<sha256>__<origName>` (origName recovered on pull so storedPath/
fileType survive a device switch), `covers/<sha256>.jpg`. Sync =
ensureDirs → readManifest (404→null) → listBooks/listCoverShas →
pull-reconcile (transaction) → push (writeManifest last). Cloud-only
docs are metadata rows with planned `storedPath`/`coverPath` but no
file: `textIndexed=1` + empty-body FTS row keeps titles/author search
working; opening one goes through the `_openDoc` download gate (cloud
badge on cards) → `downloadBook` writes the file, resets `textIndexed`,
re-runs the FTS indexer, then opens.

**Files**: `lib/features/sync/data/{webdav_sync,sync_manifest,
sync_engine}.dart`, `lib/features/sync/presentation/sync_providers.dart`
(SyncRunner is `keepAlive` — autoDispose disposed its ref mid-run:
"Cannot use the Ref of syncRunnerProvider after it has been disposed";
`ref.mounted` guards after awaits). UI: Settings "WebDAV sync" section
(connect & test, sync now, download all, remove), drawer "Sync now",
cloud badges (DocCard overlay + list tiles), auto-sync at boot and after
imports (silent, failure → snackbar). `_enrich` (metadata enrichment)
wrapped in try/catch — garbage bytes threw unawaited and killed test
zones.

**Tests: 55/55** (6 new in `test/sync_test.dart` against an in-memory
fake WebDAV: push/restore with uuid adoption, no-op second run, position
LWW both directions incl. stale-manifest protection, tombstones, and
collection/tag merge). `flutter analyze` 0 issues.

**Battery** (pixel_7, host `wsgidav` 4.4.0 anonymous on :8080 →
`/tmp/opencode/dav`, emulator at `10.0.2.2`; `DOCVIEW_BATTERY_SYNC`
define auto-configures the account; seeds are idempotent across boots —
they embed zip timestamps so sha256 dedupe alone would duplicate them):
push run (8 books + manifest uploaded), restore run (`pm clear` → pull
repopulates metadata + covers, `Library · 13` after local seed merge),
on-demand open (tap badged cloud card → download → PPTX reader opens) —
0 FATAL each. Baseline battery re-run: **all 4 AVDs FATAL- and
ANR-free**.

Releases/DocView.apk rebuilt: arm64 0.8.0+8 ≈ 33.2 MB. Open next:
Phase 8 polish (big-library perf, tablet 2-pane, notes/highlights +
export) or whatever the user picks.
