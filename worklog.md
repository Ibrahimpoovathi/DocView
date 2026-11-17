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

---

## Phase 8 — Annotations: highlights, notes, bookmarks (0.9.0+9)

**Decisions (user-approved):** fixed 5-color palette (no picker);
office readers excluded (plain-text anchors are unstable); markdown-only
export; battery = sync battery extended with a notes flow. Scope:
PDF + reflow readers only.

**Schema v6**: `Annotations` table (uuid, documentId, kind, anchor JSON,
excerpt, note, color, createdAt, nullable updatedAt, tombstonedAt —
`deletedAt`). Repository stamps `updatedAt` on every mutation; deletes
are soft; `upsertRemote` merges LWW with deletion-dominant ties.

**Reflow** (docview.html + reflow_screen): the selection bridge now
serializes the settled DOM selection with `epubcfi.fromRange` and ships
`{text, cfi}` — single-word selections keep opening the dictionary,
multi-word selections open a floating action bar (palette dots +
note). Highlights go through foliate `addAnnotation`, replayed per
section on `create-overlay`, painted via `draw-annotation` →
`Overlayer.highlight`; tapping a drawn highlight opens the editor sheet
(color dots, note field, delete). Bookmarks toggle in the app bar at
the current CFI.

**PDF** (reader_screen): context menu gains Highlight (color sheet) and
Add note; anchor = `{page, start, end}` char indices into pdfrx's
deterministic `PdfPageText` (from `getSelectedTextRanges()`); a
`pagePaintCallback` repaints line-grouped rects from `charRects`, with
page text cached lazily (loadStructuredText is async, paint is sync).
Bookmark toggle in the app bar at the current page.

**Sync**: manifest v2 adds `annotations[]` (uuid + sha256 keyed). Same
LWW + deletion-dominant-tie policy as documents. Two real bugs caught:
(1) the tie path let a device resurrect its own just-deleted annotation
from its own manifest echo — ties now keep whichever tombstone exists;
(2) the test's "same second" premise failed silently because Drift
stores DateTime at second precision while ISO-8601 round-trips keep
microseconds — tie tests floor to whole seconds.

**List & export**: annotations list sheet (grouped by kind, tap to
jump, edit via the editor, color/delete hooks keep the reflow overlay
in step), per-document Markdown export (excerpts + notes + page refs)
through the file picker.

**Tests: 63/63** (6 new: annotation repo CRUD round-trip, soft-delete
visibility, update stamping, remote upsert LWW + deletion-dominant
ties, annotation sync push/restore with tombstone propagation, and the
same-second tie test). `flutter analyze` 0 issues.

**Battery**: `DOCVIEW_BATTERY_NOTE=epub` — docview.html gains
`docviewBatterySelect` (text-walker selection in the visible section →
selectionchange → CFI bridge), the flow creates highlight + note +
bookmark, syncs (retrying while the boot auto-sync holds the runner),
and captures the annotations list. Verified runs: notes-push (server
manifest carries annotations; list renders all kinds), notes-restore
(pm clear → pull → local additions → server annotations 3 → 6 → 9
across seed generations — bidirectional merge on device). 0 FATAL
throughout. Seed idempotency guard hardened to match `battery.%` too
(a partially-imported library without mini.pdf used to re-import).
Standard baseline: all 4 AVDs FATAL- and ANR-free ("System UI isn't
responding" popups observed in notes captures are emulator host-load
noise — no app ANRs in logcat).

One host gotcha re-learned: the wsgidav config must map the `/dav`
prefix (`provider_mapping: {"/dav": ...}`) — a freshly regenerated
config that mounted the share at `/` made the app's sync fail silently
(404s) with zero FATALs; symptom was an empty server dir.

Releases/DocView.apk rebuilt: arm64 0.9.0+9 ≈ 33.2 MB. Open next:
Phase 9 polish — big-library perf, tablet 2-pane, PDF password prompt,
"last synced" indicator, README promise audit.

## 2026-11-13 — Phase 9 done (1.0.0+10)

Final polish phase — four promise gaps closed, version 1.0.0+10.

**Big-library perf**: the cloud badge on every `DocCard` and list row
called `File(...).existsSync()` inside build — one synchronous stat()
per card per rebuild, which scales linearly with library size. The
library state now computes a `cloudOnly` id set once per docs-list
emission (identity-checked, yielding every 50 docs, `SetEquality`
compare before setState) and passes it down through `_ResponsiveGrid`,
`_DocList` and `ShelfBar`; `DocCard` takes a plain `cloudOnly` bool.
Verified with a new big-lib battery (`tool/battery_biglib.sh`,
`DOCVIEW_BATTERY_BIGLIB=200` + `OPEN=none`): 208-doc seed via batched
`importBytes` (20 per batch, yielding between batches), grid capture,
4 fling scrolls. Result: 0 FATAL / 0 app ANR, cold start ≈ 3.0 s, and
every "Skipped N frames" entry confined to the seed-import window —
grid building and scrolling are jank-free. The script learned to
dismiss a host-noise "System UI isn't responding" dialog via
`uiautomator dump` before flinging (an unconditional tap once hit a
card and opened a reader instead of scrolling).

**Tablet 2-pane**: reader routes (`/reader/:docId`, plus the battery
raw route) moved into a `ShellRoute` whose builder is `_ReaderShell` —
at ≥840dp it shows the library live in a fixed 372dp left pane
(`LibraryScreen` embedded) beside the reader navigator with a
`VerticalDivider`; below 840dp it returns the plain navigator so
phones are pixel-identical to before. Opening another book from the
left pane swaps the right pane instantly (go_router push on the shell
navigator). Verified on pixel_tablet (1280dp wide): 2-pane DOCX
reading captured in the baseline battery; phones unchanged.

**PDF password**: `PdfViewer.file` accepts `passwordProvider`
directly; the screen passes one that opens a modal dialog
(barrierDismissible, obscure+autofocus text field, Cancel → null →
pdfrx throws `PdfPasswordException` → viewer error state, Unlock →
submit). pdfrx retries per wrong attempt, so the dialog reopens with
an "Incorrect password" title (attempt counter in state). Empty first
attempt (pdfrx's `firstAttemptByEmptyPassword`) opens unencrypted
files without any dialog.

**Last synced**: `SyncRunner.run` persists
`docview.lastSyncAt` (epoch ms in shared_preferences) after any
non-failed run (best-effort, wrapped in try/catch); Settings shows
"Last synced: just now/N min ago/N h ago/N d ago" (or "Never synced")
under the account tile via `FutureBuilder`, refreshed after
"Sync now".

**Tests**: 63/63 unchanged, `flutter analyze` 0 issues.

**Battery**: 4-AVD baseline (quick_phone / old_phone / pixel_7 /
pixel_tablet) FATAL- and ANR-free at 1.0.0+10; tablet leg shows the
2-pane shell; pixel_7 confirms narrow phones still get the
full-screen reader. Big-lib battery FATAL-free (see above). Release
rebuilds: split arm64 → `releases/DocView.apk` (1.0.0+10 ≈ 33.4 MB,
aapt-verified), baseline battery `app-release.apk` (94.6 MB), big-lib
battery build built + exercised.

README updated (1.0.0, Phase 9 row Done, 2-pane tablet row, big-lib
battery table + BIGLIB define, Phase 9 notes paragraph).

Open next: nothing planned — all README promises audited and closed.
Possible future work: DOCX selection for dictionary/annotations
(fork deferred from Phase 6), integration-test execution on emulator
(host-RAM deferred), iOS/CUDA platform runs.

## Stage D/D+ audit — runtime edge battery, sync-fail, tablet rotation, monkey (1.0.0+10)

**Edge battery (3 rounds × 10 boots, quick_phone)** — 0 FATAL across all
runs. Verified working: PDF password flow (prompt → wrong-password error →
unlock 'batpass' → renders), CBZ with valid PNGs, malformed MOBI →
graceful foliate error. Findings:
- **HIGH huge.txt (50MB)**: reader blank at 0% for 8+ min, conversion
  never completes — `book_server.dart` `/txt/` runs `txtToEpub`
  synchronously on the main isolate with an unbounded `_txtCache`;
  `/files/` serves via whole-file `readAsBytes()`.
- **MEDIUM corrupt PDFs** (truncated/empty/garbage): raw pdfrx blue error
  banner WITH stack trace in release — needs `errorBannerBuilder` or
  pre-validation.
- **MEDIUM fb2 pagination**: page 1 renders, section pages → paginator.js
  destructure TypeError (malformed fb2) or native WebView **renderer
  crash** `aw_browser_terminator.cc(165) code -1` (valid fb2) → blank page.
- Verified non-bugs: boot auto-open ordering (markOpened correct via DB
  query), empty.txt/empty.pdf sha256 dedup collision (count 9/10).
- Test-file fixes: valid sample.fb2 XML, real-PNG sample2.cbz, fixed
  sample.epub (`<meta>` → `<metadata>`; verified rendering on tablet).

**Tooling root cause found mid-leg**: battery scripts installed the stale
fat `app-release.apk` (edge-only defines) — sync define never baked →
sync silently absent in earlier sync legs. All 8 tool scripts now install
the x86_64 split APK; rebuilt APK defines verified via `strings
libapp.so`.

**Sync-fail leg (4 boots, quick_phone)**: boot1 account setup (secure
storage write verified via shared_prefs), boot2 push (dav gains
manifest.json/books/covers), boot3 wsgidav-down → "Sync failed:
DioException… Connection refused" snackbar captured at ~t+6s (fails fast,
not the 20s connect timeout), 0 FATAL, boot4 recover clean. Library
growth 8→18 across runs is correct two-way manifest merge (old battery
runs' differently-hashed books pulled back), not a bug.

**Tablet rotation leg (pixel_tablet)**: natural landscape 2000×1200 →
2-pane (372px library + reader) ✓; user_rotation 1 → portrait 1200×2000 →
reader full-screen (<840dp) with reflow ✓; back to landscape → 2-pane
restored ✓. Fixed epub renders in both orientations. 0 FATAL. Recurring
"System UI isn't responding" dialogs are com.android.systemui ANRs
(emulator/swiftshader artifact), never the app (no app ANR lines in
logcat).

**Monkey (Stage D+)**:
- Stock quick_phone: 20,000 events, seed 42, throttle 50ms → exit 0,
  0 FATAL, PSS 147→149 MB (no leak), 43 rotation flips survived.
- Stock pixel_tablet: 20,000 events, same seed → exit 0, 0 FATAL,
  PSS 149→149 MB, no renderer crashes.
- **fb2 WebView renderer crash reproduced under monkey** (twice at
  03:18:14) → blank reader state (no app crash) — Stage E HIGH.
- Reader-stress (tool/battery_monkey_stress.sh, 6 rounds: 12+6+2 swipes,
  chrome taps, back+reopen, rotation flips): quick_phone 0 FATAL /
  0 renderer crashes, PSS 125→155 MB; pixel_tablet variant 0 FATAL /
  0 renderer crashes, PSS 147→152 MB.
- gfxinfo jank metrics unusable on swiftshader emulator (GPU percentiles
  ≈4950ms artifact) — real-device perf check remains open.

New tool: tool/battery_monkey_stress.sh (coordinate-tuned for quick_phone;
tablet run used adapted inline coords). Probe servers: probe8081.py
(python DAV stub used to isolate the APK-defines issue; kill when done).

Stage E queue (fix everything): txtToEpub isolate+size-cap+LRU cache +
streaming /files/; pdfrx errorBannerBuilder; fb2 paginator null-el guard
+ renderer-crash root cause; sync mount-race hardening (_batterySyncSetup
unawaited vs _autoSync; autoSync skipped when reader unmounts library);
all Stage A/B/C findings; fresh-epub-open progress slider 100% check;
delete /tmp/opencode/pylib after audit.

---

## Stage E — fix everything found (2026-11-14, 1.0.1+11)

All fixes landed, full suite green, batteries re-verified.

**fb2 renderer crash — root-caused and fixed (HIGH)**: opening fb2 crashed
the WebView renderer (aw_browser_terminator code -1) → route unmounted →
dispose cascade (pdfrx null _state + unmounted-ref errors) → blank gray
screen. Fix: new lib/features/reader/data/fb2_to_epub.dart converts
FictionBook 2 → EPUB 3 entirely in Dart (sections/titles, p/poem/cite/
epigraph, inline styling, anchors, tables, base64 `binary` images as data
URIs; labeled blocks keep TOC entries, 12k-char chunks; text escaping).
book_server.dart gained an LRU-cached, isolate-based `/fb2/` route
(_convertCache replaces _txtCache); reflow_screen routes DocFormat.fb2
docs to it — foliate fb2.js is now never used. Verified on quick_phone:
fb2 opens, h1/h2 + paragraphs render, pagination works, TOC-sheet and
annotations-sheet open cleanly, 0 FATAL / 0 exceptions. 3 unit tests in
test/fb2_epub_test.dart (sections+metadata, empty body/unknown elements,
escaping + long-section split).

**Dispose cascade (HIGH)**: reader_screen._flushSave no longer touches
pdfrx for non-PDF docs (null _state crash); reflow_screen captures
ReadingRepository in a late field at initState — dispose/Timer callbacks
never call ref.read (unmounted-ref crash).

**WebView resilience**: reflow_screen onRenderProcessGone now swaps in a
friendly EmptyState instead of leaving a dead blank webview.

**Sync (HIGH)**: library_screen chains `_batterySyncSetup().then(_autoSync)`
— account save must complete before boot auto-sync reads the store (first
boot could silently skip the push); SyncEngine.run() gained a static
re-entrancy guard (overlapping boot/import/manual syncs returned an empty
SyncResult instead of interleaving manifest read-modify-writes).

**Other fixes**: pdfrx errorBannerBuilder → friendly EmptyState for
corrupt PDFs (was raw stack-trace banner); database.dart onUpgrade guards
every ALTER ADD COLUMN with a PRAGMA table_info check (duplicate-column
crash on partially upgraded DBs); text_index pending backlog now indexes
newest docs first; _ensurePdfText dedupes in-flight loads (paint callbacks
can fire per frame) + bounds its cache (clears past 64 pages); PDF
annotations list now reloads _annotations after sheet edits (stale
overlay); office_screens XLSX/TextDoc dispose their ScrollControllers;
reflow _dictDebounce cancelled in dispose; all stray reflow prints
removed; intl + cupertino_icons dropped from pubspec; docview.html
docviewToc dead `walk` duplicate removed.

**Verification**: flutter analyze clean; full test suite 72/72 green.
Same-seed (42) 20k-event stock monkey re-run: exit 0, 0 FATAL, 0 ANRs,
0 renderer crashes, PSS 150 MB, 54 flips. (First same-seed attempt on a
memory-starved host hit an ANR at event 14487 — ANR trace showed the main
thread idle in epoll, 18% iowait, host down to 916 MB available; same seed
passed cleanly on a fresh boot. Environmental, not an app regression.)
Sync leg re-verified with the new APK: boot 1 push (manifest 8 docs +
books + covers within 60 s of cold start — race fix proven), boot 2
restore (Library · 13, covers render), 0 FATAL across both boots.

**Release**: version bumped to 1.0.1+11; releases/DocView.apk rebuilt from
app-arm64-v8a-release.apk (33.4 MB); prod APK verified free of battery
defines (strings check: 0 hits for 10.0.2.2).

## Stage F — second-audit fixes + DOCX pagination (2026-11-15, 1.0.2+12)

**DOCX now opens as a paginated PDF.** `docx_creator`'s `PdfExporter`
converts the .docx in an isolate (`lib/features/reader/data/docx_pdf.dart`)
into `books/<uuid>/docview-converted.pdf`, cached until the book is deleted
(re-import gives a fresh uuid so the cache can never go stale). The reader
shows it in pdfrx with a page indicator; search remains paragraph-based and
maps hits → pages, progress is stored as a page number. Files >20 MB (or
unparsable) fall back to the old `docx_file_viewer` widget. Verified on
quick_phone: A4 page card, table/bullets render, "Page 1 of 1", PDF load
26 ms. Real page geometry was the Phase-1 item that was silently missing.

**Storage waste**: import now always clears file_picker's temp copies in a
`finally`; the document options sheet offers "Remove local copy (keep in
cloud)" (confirm dialog) when a WebDAV account exists, and the library
re-checks cloud-only state via `localCopyRevisionProvider`. Originals are
never moved/deleted (Option A).

**Release blockers**: (1) adaptive launcher icon generated at every density
+ Android-13 monochrome (`/tmp/opencode/make_icon.py`, serif "D" + amber
rule); (2) signed release keystore outside git (`~/.docview-keystore/`,
`android/key.properties` 600 + gitignored), debug fallback for CI-less
builds; (3) open-with/share — manifest VIEW/SEND filters (content+file
URIs, full mime list, extension pathPatterns, `<queries>`), `MainActivity`
MethodChannel `docview/open_with` with `takePending`/`onNewIntent`,
content URIs copied to `cacheDir/open_with`; imports route straight into
the reader and delete the temp copy; (4) cleartext limited to 127.0.0.1 /
localhost (+10.0.2.2 for the emulator battery) via
`network_security_config.xml`; Settings rejects non-https WebDAV except
loopback.

**Correctness**: re-import of a deleted book no longer crashes on
`UNIQUE(sha256)` — `findBySha256(includeDeleted)` + `reviveDocument`
(reuses uuid, resyncs FTS meta); BookServer gained a per-launch random
token (query/header/cookie `dv_t`, Set-Cookie for module imports, unknown →
404) threaded through reflow and dictionary URLs; annotations are
uuid-addressed in `docview.html` (`annotationsByValue` arrays +
`annotationsByUuid`), fixes duplicate-CFI highlights; anchor parsing is
lenient + memoised (`tryParseAnchor`); FB2 decoding handles UTF-8/UTF-16
BOMs, declaration charsets and cp1251 bodies, escapes `"` in attributes and
caps conversion at 15 MB with a friendly page; TXT cap got the same page;
PDF text extraction now reads page 0 (was 1); dictionary lookup times out
at 5 s and online lookup defaults off; `createCollection` returns the
existing row instead of throwing; one poisonous document no longer stalls
the background indexer; schema v7 + manifest v3 add collection/tag
tombstones with LWW merges (deletions win ties); sync downloads stream to
`.part`, verify the sha256 while hashing and only then rename; covers are
fetched outside the DB transaction.

**Perf/polish**: import sha256 + EPUB metadata extraction in isolates; XLSX
virtualised (fixed row extent, sampled column widths, horizontal
scroll); theme switches repaint in place via `docviewSetColor` instead of
rebuilding the WebView; CSP meta on both HTML assets; MIT LICENSE + OFL
texts for the bundled fonts; `deleteDocument` cascades positions/group
links and tombstones annotations.

**Verification**: `flutter analyze` clean; `flutter test` 79/79 green (new
`test/regression_test.dart`: DOCX→PDF geometry/cache, re-import revival,
collection/tag tombstones, legacy manifest, cp1251 FB2, BookServer token).
Battery x86_64 build: DOCX page-geometry screenshot, resume round-trip, 0
FATAL; WebDAV restore after `pm clear` pulled all 8 books via the new
streaming+sha path, manifest v3 on the server, 0 FATAL (one host-load
"System UI isn't responding" dialog — known emulator artifact, app had no
ANR). Edge leg not re-run this round (its `/dav/edge` needs an anonymous
host mount; previously verified in Stage D).

**Release**: 1.0.2+12, `releases/DocView.apk` rebuilt from
`app-arm64-v8a-release.apk` (34.7 MB), signed with the new DocView
keystore (CN=DocView), battery defines absent (strings check: 0 hits).

---

## 2026-11-16 · 1.0.3 — Error-free & bloat-free pass (Phases 1–5)

**What was done**

- **Lifecycle leaks (1.1/1.2)**: `_pdfPasswordProvider` always disposes its
  controller; `BookServer` is now ref-counted (`acquire`/`release`), dedupes
  concurrent `serve` calls (`_starting`), and exposes `resetAfterCrash()`.
  Reflow holds a ref for its lifetime and resets the server on
  `onRenderProcessGone`; the dictionary sheet acquires/releases around its
  live WebView.
- **SharedPreferences (1.3)**: single `sharedPreferencesProvider`
  (override in `main`), `LibraryPrefs` hydrates synchronously from it and
  persists grid/sort/chip; settings, dictionary, sync providers read the same
  instance instead of awaiting `getInstance` ad hoc.
- **Undo delete without data loss (1.4)**: delete now tombstones and keeps
  artifacts; a 6 s Undo snackbar revives (textIndexed reset) or purges on
  timeout; boot sweep `purgeAbandonedArtifacts()` clears leftovers;
  annotation tombstones only when not already deleted.
- **Consistent back affordance (1.5)** + covers rendered at 480 px (2.1),
  PDF text LRU touch (2.2), batched imports of 4 with same-batch claim set
  and unique-constraint arbitration (2.3), staggered list limited to the
  first 20 rows (2.5).
- **Battery seeder extraction (3.1)**: ~360 lines moved out of
  `library_screen.dart` into `library/data/battery_seeder.dart`; the battery
  build also seeds a "Battery set" collection for chip testing.
- **Library UX (4.1–4.3)**: collection filter chips (session-only
  `collectionId` on prefs/query; exists-subquery in drift and SQL FTS paths;
  mutually exclusive with All/Bookmarks/Recent); the end drawer became a
  modal tools sheet; imports report `ImportProgress{done,total}` and show a
  thin linear bar under the chips.
- **Immersive PDF reading (4.4)**: tapping the page toggles the bar chrome
  (`AnimatedSize`, PDF viewer only; reflow untouched).
- **Tests (5.1/5.2)**: `fts_match_query_test.dart` (8 cases) and
  `import_service_test.dart` (4 cases incl. same-batch duplicates).
- Dropped 3.2/3.3/2.4 after review: `docx_creator` is a production
  dependency (DOCX→PDF), the annotation mixin rewrite is high-risk/low-value,
  and the static indexer guard is already correct.

**Verification**: `flutter analyze` clean; `flutter test` 91/91 green.

**Release**: 1.0.3+13, arm64 `releases/DocView.apk` rebuilt signed.

---

## 2026-11-16 · 1.0.4 — Blank-on-second-open regression

**Bug**: after a first document rendered fine, every later open showed a
blank gray screen (reproducible after PDF→Back→EPUB on quick_phone).

**Root cause** (logcat): pressing Back after a PDF threw during dispose —
`Null check operator used on a null value`, `PdfViewerController._state` →
`pageNumber` → `_ReaderScreenState._flushSave` → `dispose`. pdfrx detaches
the controller before the parent disposes, so the flush crashed a frame and
later pushes painted nothing. In the same pass the in-body AppBar turned out
to have no visible back arrow.

**Fixes**

- `reader_screen.dart`: `_readingRepo` captured once in `initState`;
  `_flushSave` no longer touches `ref` or `_ctl.pageNumber` (uses
  `_pageNumber`); `_load` guarded → `_loadError` EmptyState with Back;
  restored page clamped and applied after `onViewerReady`; explicit
  `arrow_back_rounded` IconButton in the in-body AppBar.
- New `reader/domain/restore.dart`: `clampRestoredPage`, `sanitizeProgress`,
  `sanitizeLocation` (length-bounded); used by reflow, office and PDF paths.
- `reflow_screen.dart`: restore state is sanitized **before** the
  `_bookUrlFuture` is created (positions were silently dropped before);
  FutureBuilder shows `_error` before the loader; renderer crash clears the
  stale URL future; AppBar gained an explicit back arrow.
- `book_server.dart`: `stop()` keeps the per-launch token so held document
  URLs stay valid; `resetAfterCrash()` no longer zeroes the refcount and
  restarts the socket when consumers remain.
- `main.dart`: friendly `ErrorWidget.builder` plus global
  `FlutterError.onError` / `PlatformDispatcher.instance.onError` logging, so a
  rendering failure can never look like a silent gray screen again.
- `office_screens.dart`: sanitized restore, clamped page, explicit back
  arrow in the shared office AppBar.

**Verification**: `flutter analyze` clean; `flutter test` 100/100 green
(new `test/restore_test.dart` with 9 cases; `regression_test.dart` gained a
"token survives stop/restart" case). Manual reopen matrix on quick_phone:
PDF→Back→PDF, PDF→Back→EPUB, EPUB→Back→EPUB, DOCX→Back→DOCX, XLSX, TXT —
all render, back arrows visible, 0 `E/flutter`, 0 NULL-check, 0 FATAL.
`tool/battery_all.sh` across quick_phone / old_phone / pixel_7 /
pixel_tablet: ALL FATAL-FREE; tablet 2-pane PDF and EPUB reopen with the
library pane live and progress restored (8%).

**Release**: 1.0.4+14, arm64 `releases/DocView.apk` rebuilt signed,
battery defines absent.

---

## 1.0.5+15 — 2026-11-17 — Correctness + reader typography pass

Post-1.0.4 review against the worklog: five audit findings were already
covered by earlier stages and are **not** regressions (battery scaffolding is
compile-time and tree-shaken; the renderer-crash dead-end, dependency pins,
XLSX row virtualization and the silent-catch surface were all handled in
Stages E/F and 1.0.4). The items below were still live in the code.

**Fixes**

- `settings_screen.dart`: the online-dictionary switch read
  `?? true` while the lookup path used `?? false`, so a fresh install showed
  the toggle **on** with lookups actually offline. Both now default to false
  (Stage F intent: online lookup is opt-in). Added a **Recent lookups**
  section — `LookupHistory` recorded every hit but nothing ever displayed it.
  Words are tappable and re-open the sheet; Clear empties the list.
- `dictionary_sheet.dart`: `_lookup()` only ever consulted `dicts.first`, so
  a second imported StarDict was silently ignored. It now iterates every
  imported dictionary and stops at the first non-empty hit, skips the online
  fallback when an offline dictionary answered, and writes history only for
  real hits. Providers are read before the first `await` so a dismissed sheet
  cannot touch a disposed `ref`.
- `reflow_screen.dart`:
  - Scroll progress updated `_fraction` / `_permilleViewed` / `_location`
    with no `setState`, so the bottom bar's slider and bookmark stayed stale
    while reading. `onReflowProgress` now calls a 120 ms-coalesced
    `_scheduleChromeRefresh()` instead of rebuilding per bridge event.
  - `onLoadStop` called `setState` with no `mounted` guard — popping the route
    mid-load threw.
  - Search results could repopulate a search the user had already closed; the
    handler returns early when `!_searchOpen` and the dead empty `if` is gone.
  - `_jsonStr` now uses `jsonEncode` (it only escaped single quotes, so a TOC
    href containing a backslash or newline broke the injected JS).
  - **New typography controls**: a "Text size and spacing" sheet with font
    size (70–180%) and line spacing (1.2–2.2) sliders plus Reset. Values are
    global, persisted (`docview.fontPercent` / `docview.lineSpacing`), passed
    in the page URL for the first paint, and applied live to every rendered
    section through `window.docviewSetTypography`.
  - Accessibility: highlight swatches have `Semantics` labels and 48 dp tap
    targets; search excerpts honour the system font scale via `textScaler`.
- `reader_chrome.dart`: optional `onTypography` action on the bottom bar
  (null on the PDF reader, which has no reflowable text).
- `office_screens.dart`: search-excerpt `RichText` honours `textScaler`.
- `assets/foliate/docview.html`: `TYPO` state from `size`/`spacing` params,
  `pageCSS()` drives `font-size`/`line-height`, and `injectStyles` /
  `applyStyles` replace the no-op `renderer.setStyles` (this paginator has no
  `setStyles`, so live restyling rewrites the injected `<style>` in each live
  content document via `getContents()`).
- `.github/workflows/ci.yml`: `flutter analyze` + `flutter test` on push and
  PR — the tests existed but nothing ran them automatically.
- `pubspec.yaml`: 1.0.5+15.

**Verification (and its limits)**

- AppJet `project` preset: source review passed (128 files, no conflict
  markers).
- Dependency security: 198 Pub packages, 0 high/critical findings; reported
  **incomplete** because the Android Gradle files have no resolved lockfile.
- No Flutter/Dart SDK in this environment, so `flutter analyze`,
  `flutter test` and an APK build were **not** run here. Every changed call
  site was checked against its real signature (`showDictionarySheet(context,
  ref, word)`, `ImportedDict.bookName`, `DictionaryEntry.meanings`,
  `LookupHistory.recent/record/clear`, `paginator.getContents()`). The new CI
  workflow is what should confirm analyze/test green on the next push.

### 1.0.5+15 — Dependency security: Kotlin Gradle plugin advisory fixed

The dependency scan cannot resolve the Android Gradle graph (no `gradle.lockfile`
in the repo and no Android SDK here to generate one), so the declared build
artifacts were checked directly against OSV.

**Found and fixed**

- `GHSA-r937-wjx7-w2jp` / `CVE-2026-53914` — JetBrains Kotlin *before 2.4.20*:
  unsafe deserialization in build-cache metadata enables code execution.
  `android/settings.gradle.kts` pinned `org.jetbrains.kotlin.android` at
  **2.4.0**, inside the affected range. Bumped to **2.4.21**, the latest stable
  2.4.x patch (OSV reports 0 advisories for 2.4.20 and 2.4.21).

**Checked, no advisories**

- `com.android.tools.build:gradle` 9.1.0 (AGP)
- `androidx.test:runner` 1.6.2, `androidx.test:rules` 1.6.1,
  `androidx.test:monitor` 1.6.1, `androidx.test:junit` 1.2.1
- `androidx.test.espresso:espresso-core` 3.6.1,
  `androidx.test.espresso:espresso-idling-resource` 3.6.1

**Still uncovered — needs an Android SDK / Gradle resolution**

- The transitive Gradle dependency graph: AGP and Kotlin pull hundreds of
  artifacts that only dependency resolution reveals.
- The Gradle 9.3.1 distribution itself; OSV has no ecosystem entry for Gradle
  distributions, so this pipeline never scans it.

To close it: enable Dependabot for the `gradle` ecosystem, or resolve the graph
on a machine with the Android SDK and commit the resulting lockfile. Pub
coverage is unaffected (198 packages, 0 findings).

## 2026-11-17 — Vendored reader JavaScript: fflate CVE fixed

**Scope:** `assets/foliate/ext/` — third-party JavaScript bundled into the reader
webview. No `package.json`, no lockfile and no version strings, so no
manifest-based scanner covers it; the audit was manual.

**Libraries identified by content:** `@zip.js/zip.js` (36,512 B) and `fflate`
(3,857 B, exporting only `unzlibSync`).

**Found and fixed:** `GHSA-px8p-9vwx-vf98` / `CVE-2026-45820` — fflate before
0.8.3 loops indefinitely in ZIP64 central-directory parsing when an entry
declares `compressed_size=0xFFFFFFFF` without the extra-field tag `0x0001`,
a denial of service reachable from a user-supplied book. Because the bundled
copy carried no version, it was replaced rather than version-identified:
`assets/foliate/ext/fflate.js` is now the official **fflate 0.8.3** ESM browser
build (90,922 B) taken from the npm tarball.

**Contract preserved:** `view.js:113-114` dynamically imports `./ext/fflate.js`
and passes `fflate.unzlibSync` into `new MOBI({ unzlib })`; the replacement still
exports `unzlibSync`.

**Verified:** node round-trip against the committed copy —
`unzlibSync(zlibSync(text))` returned 6,500 identical bytes.
`@zip.js/zip.js` returns no advisories in OSV (package-wide query).

**Still uncovered:** these two files are inferred from content rather than
declared, and nothing records their versions, so future updates stay manual.
