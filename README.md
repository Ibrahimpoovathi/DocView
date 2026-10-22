# DocView — Local-First Document Reader

A Flutter document reader for Android and iOS: PDF, EPUB, Office documents
(DOCX/XLSX/PPTX), comics and common ebook formats — private by design with
optional user-owned WebDAV sync.

## Status

| Phase | Scope | Status |
|---|---|---|
| 0 | Scaffold, core stack (riverpod/go_router/drift), 3-app reference study | Done |
| 1 | Import + library (covers, recents, collections, tags, continue-reading) | Done |
| 2 | PDF reader (pdfrx: TOC, search, bookmarks, dark/fit modes, progress) | Next |
| 3 | Reflow readers (foliate-js: EPUB/MOBI/AZW3/FB2/TXT, CBZ pager, themes) | Planned |
| 4 | Office: DOCX native, XLSX tables, PPTX/DOC/ODT/RTF text-first | Planned |
| 5 | Search (in-doc + library FTS5), dictionary popup (offline + online) | Planned |
| 6 | WebDAV sync (books + progress + notes/collections, on-demand download) | Planned |
| 7 | Polish: big-library perf, tablet 2-pane, notes export, release pipeline | Planned |

Current build: **0.2.0** (Phase 0 shell + Phase 1 library). See [STUDY.md](STUDY.md) for the
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

- Deliverable: **`releases/DocView.apk`** — arm64-only release build (v0.2.0+2 ≈ 29.7 MB),
  committed to git; regenerated and *overwritten* at the end of every change.
- Command to reproduce: `~/flutter/bin/flutter build apk --release --split-per-abi`,
  then copy `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` → `releases/DocView.apk`.
- Emulator/device testing uses the x86_64 split from the same command
  (`app-x86_64-release.apk`) — never committed.
- Version bumps: pubspec `version` + worklog note each update.

### Test results at current build (0.2.0+2)

Static: `flutter analyze` — 0 issues; `flutter test` — 10/10 pass
(format detection, repository CRUD + soft delete, import pipeline incl.
dedupe-by-sha256 and unsupported-file handling, empty-library widget test).

AVD battery (install, cold launch, screenshot review, FATAL/ANR logcat scan):

| AVD | API | Result |
|---|---|---|
| quick_phone (ATD) | 35 | ✅ clean; empty library renders (error screen fixed via sqlite3_flutter_libs) |
| old_phone | 30 | ✅ clean |
| pixel_7 | 36 | ✅ clean |
| pixel_tablet | 36 (landscape) | ✅ clean, layout adapts |

Integration-test harness (`integration_test/app_test.dart`) remains in place;
execution on emulator still deferred for the host-RAM reason in the worklog.

## Docs

- [STUDY.md](STUDY.md) — ReadEra / anx-reader / Readest architecture & feature study
- [worklog.md](worklog.md) — chronological build log (every session, dated)
