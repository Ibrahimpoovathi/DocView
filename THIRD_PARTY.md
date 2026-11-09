# Third-party components bundled in DocView

## Fonts (assets/fonts/)

- **Fraunces** and **Inter** — Google Fonts via google/fonts (SIL Open Font
  License 1.1). Full license texts ship next to the TTFs (`Fraunces-OFL.txt`,
  `Inter-OFL.txt`).

## foliate-js (assets/foliate/)

- Copyright (c) 2022 John Factotum, MIT License. Used for reflow rendering of
  EPUB / MOBI / AZW3 / FB2 / CBZ inside the reader WebView (served from the
  app-owned local HTTP server). The included subset excludes `vendor/pdfjs`,
  tests, and build tooling. Upstream: https://github.com/johnfactotum/foliate-js
- `ext/zip.js` and `ext/fflate.js` follow their upstream MIT licenses.

## Dart packages

All dependencies are declared in `pubspec.yaml` with their own licenses
(check `pubspec.lock`); the notable rendering engine is **pdfrx**
(MIT, Apache pdfium).

- **docx_file_viewer** + **docx_creator** — Apache-2.0/MIT (repo LICENSE),
  native Flutter DOCX widgets and the underlying DOCX build/parse model.
- **excel_plus** — MIT, streaming XLSX reader (also reads legacy .xls).
