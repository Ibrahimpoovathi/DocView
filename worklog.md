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
