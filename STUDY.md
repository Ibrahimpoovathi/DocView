# DocView Reference-App Study (Phase 0)

Benchmark sources: **ReadEra** (offline APK, v26.05.20+2300), **anx-reader**
(Flutter, MIT, ~9k★), **Readest** (Tauri, AGPL, ~23k★). Examined Oct 21 2026.

## 1. ReadEra — APK analysis (native Android benchmark)

Identified engines from bundled licence/readme assets (`assets/era*`):

| Engine | Formats | Based on | Licence |
|---|---|---|---|
| EraPDF | PDF | MuPDF, FreeType, libjpeg-turbo, jbig2dec, OpenJPEG | AGPL-3.0+ |
| EraEPUB | EPUB, FB2, FB3, **DOC, DOCX, ODT, RTF, CHM, TXT** | CoolReader, Antiword, chmlib | GPL-2.0 |
| EraMOBI | MOBI, AZW, AZW3 | libmobi | AGPL-3.0+ |
| EraDjVu | DjVu | (own/OpenReadEra) | — |
| EraComic | CBZ/CBR-class comics | (own/OpenReadEra) | — |

Manifest facts: `org.readera`, minSdk 16 (!), targetSdk 36, no DRM guards —
`MANAGE_EXTERNAL_STORAGE`, WAKE_LOCK, FOREGROUND_SERVICE media playback
(read-aloud service), POST_NOTIFICATIONS, and a custom signed permission
`org.readera.permission.TierSync` (their private "TiER" cloud sync).

**Key product insight:** DOC/DOCX/ODT/RTF are routed *through the EPUB reflow
engine* (one pipeline), not a page-faithful renderer. Validates our
"parse & re-render" office approach. Sources: readera.org/book-reader/OpenReadEra.

## 2. anx-reader — Flutter reference (buildable architecture)

Verified from source (cloned):

- **Rendering:** bundles foliate-js (`assets/foliate-js/`), served via `shelf`
  local HTTP server into `flutter_inappwebview`. Formats EPUB/MOBI/AZW3/FB2/TXT
  (+PDF via separate pipeline).
- **⚠️ WebView fork:** they ship their own fork
  (`Anxcye/flutter_inappwebview@4a275c3`) — presumably to fix exactly the AGP
  build breakage we hit with the pub.dev version. Confirmed Dec 2024+: pub.dev
  flutter_inappwebview 6.1.5 stable is stale; 6.2.0-beta.3 + android
  1.2.0-beta.3 build against modern AGP.
- **Office/text:** `service/convert_to_epub` — **converts non-EPUB reflow
  formats to EPUB** and reads through one pipeline (canonicalization strategy).
- **Sync:** `service/sync/webdav_client.dart` on a **vendored webdav_client
  fork** (redirect 301/307/308 fixes, #345) + `database_sync_manager.dart`
  pattern. Books + progress + notes sync.
- **TTS:** system TTS + Azure/OpenAI/Aliyun cloud backends, sleep timer.
- **AI:** langchain-based quick prompts, on-demand dictionary/translation, key
  rotation (`service/ai/`).
- Extras: reading stats, MD5 book dedupe (`md5_service.dart`), share-intent
  receive (`service/receive_file/`), notes export TXT/MD/CSV.

## 3. Readest — feature/strategy reference (web-stack)

Verified from source: Tauri (Rust) + Next.js/React, vendored `packages/foliate-js`,
**js-mdict** (MDX/MDD dictionary support — huge dictionary ecosystem),
simplecc-wasm (zh simplified/traditional conversion), own sync server ("+ TTS",
KOSync-style), AGPL-3.0. Community plugins: Calibre, KOReader, Crosspoint.

**Adopt-worthy:** .mdict dictionary format support (P5), reading-position
sync interoperability mindset, strong typography defaults.

## 4. Decisions for DocView

1. **Reflow = foliate-js in WebView** (validated by both references).
   Use `flutter_inappwebview 6.2.0-beta.3` (pinned, builds clean vs AGP);
   if stable/patched pub.dev release lands or regressions appear → switch to
   Anxcye fork pattern.
2. **PDF = pdfrx (MIT/pdfium)** — avoids AGPL MuPDF entirely; license hygiene
   keeps us commercially safe.
3. **Office:** DOCX native (`docx_file_viewer`), XLSX native (`excel_plus`),
   PPTX/DOC/ODT/RTF text-first via extraction (`office_oxide_ffi`). Revisit
   `offline_document_viewer` for bundled-engine option.
4. **Canonicalization option:** mirror anx-reader's convert→EPUB for
   MOBI/FB2/TXT in P3 if foliate-js render quirks arise (keep both paths).
5. **Sync = WebDAV** with vendored-redirect-fork fallback if pub.dev
   webdav_client needs patches; DatabaseSyncManager-style drift+delta sync.
6. **Dictionary P5:** offline WordNet/Wiktionary first; evaluate .mdx support
   (js-mdict ecosystem) as stretch.

## 5. Feature matrix (what "good" looks like)

| Feature | ReadEra | anx-reader | Readest | DocView target |
|---|---|---|---|---|
| PDF | ✅ | ✅ | ✅ | ✅ P2 |
| EPUB reflow | ✅ | ✅ | ✅ | ✅ P3 |
| MOBI/AZW3/FB2 | ✅ | ✅ | ✅ | ✅ P3 (via foliate-js) |
| CBZ comics | ✅ | ✅ (archive) | ✅ | ✅ P3 |
| DOCX native view | ✅ (reflow) | — | — | ✅ P4 |
| XLSX/PPTX view | ✅ (limits) | — | — | ✅ P4 (text-first) |
| Full-doc search | ✅ | ✅ | ✅ | ✅ P5 (FTS5 library) |
| Dictionary popup | — | ✅ AI | ✅ mdict | ✅ P5 offline |
| TTS | ✅ service | ✅ +cloud | ✅ | stretch |
| Cloud sync | TiER (closed) | WebDAV ✅ | own server | ✅ P6 WebDAV |
| Notes/highlights export | ✅ | ✅ TXT/MD/CSV | ✅ | P7 |
| 2-pane tablet reading | — | todo | ✅ | P7 |
| A11y/RTL | ✅ | ✅ l10n | ✅ | P7 |

## 6. Open questions / risks

- flutter_inappwebview 6.2.0-beta.3 on **iOS** (audio/rotation) — verify in P3.
- John's webdav redirect patch needed (like anx) once real Nextcloud used (P6).
- `.mdx` dictionary licensing — bundle empty store, user-import only.
