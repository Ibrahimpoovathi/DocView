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
