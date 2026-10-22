/// Supported document formats and best-effort detection (extension first,
/// magic bytes second).
enum DocFormat {
  pdf('PDF'),
  epub('EPUB'),
  docx('DOCX'),
  xlsx('XLSX'),
  pptx('PPTX'),
  txt('TXT'),
  cbz('CBZ'),
  mobi('MOBI'),
  azw3('AZW3'),
  fb2('FB2'),
  rtf('RTF'),
  doc('DOC'),
  odt('ODT'),
  other('DOC');

  final String label;
  const DocFormat(this.label);

  static DocFormat detect(String fileName, {List<int>? magicHead}) {
    final ext = fileName
        .toLowerCase()
        .substring(fileName.lastIndexOf('.') + 1);
    final byExt = _byExtension(ext);
    if (magicHead != null) {
      final refined = _refineWithMagic(byExt, magicHead);
      if (refined != null) return refined;
    }
    return byExt;
  }

  static DocFormat _byExtension(String ext) => switch (ext) {
        'pdf' => DocFormat.pdf,
        'epub' => DocFormat.epub,
        'docx' || 'docm' => DocFormat.docx,
        'xlsx' || 'xlsm' => DocFormat.xlsx,
        'pptx' || 'pptm' => DocFormat.pptx,
        'txt' || 'text' || 'md' => DocFormat.txt,
        'cbz' => DocFormat.cbz,
        'mobi' || 'prc' => DocFormat.mobi,
        'azw3' || 'kfx' => DocFormat.azw3,
        'fb2' => DocFormat.fb2,
        'rtf' => DocFormat.rtf,
        'doc' => DocFormat.doc,
        'odt' => DocFormat.odt,
        _ => DocFormat.other,
      };

  /// Refines a zip-family guess (epub vs ooxml vs cbz) and catches plain
  /// extensions that lie.
  static DocFormat? _refineWithMagic(DocFormat guess, List<int> head) {
    final isZip = head.length >= 4 &&
        head[0] == 0x50 &&
        head[1] == 0x4B &&
        (head[2] == 3 || head[2] == 5);
    final isPdf = head.length >= 5 && String.fromCharCodes(head).startsWith('%PDF-');
    final isMobi = head.length >= 68 &&
        String.fromCharCodes(head.sublist(60, 68)) == 'BOOKMOBI';

    if (isPdf) return DocFormat.pdf;
    if (isMobi) return DocFormat.mobi;
    if (!isZip) return null; // non-zip data: trust the extension

    // Zip container: find "EPUB" in the earliest bytes (mimetype is stored
    // first, uncompressed, by spec-conformant EPUBs).
    final ascii = String.fromCharCodes(head);
    if (ascii.contains('application/epub+zip')) return DocFormat.epub;

    // OOXML/odt/cbz: extension is already the best signal we have cheaply.
    return null;
  }
}
