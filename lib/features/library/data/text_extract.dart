import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:xml/xml.dart';

import '../../../core/format/doc_format.dart';
import '../../reader/data/docx_text.dart';
import '../../reader/data/odt_text.dart';
import '../../reader/data/pptx_text.dart';
import '../../reader/data/rtf_text.dart';

const _maxBodyChars = 1_500_000;
const _maxPdfPages = 500;

/// Formats whose body text is pulled into the FTS5 index. The rest (mobi,
/// azw3, fb2, cbz, doc, ppt, other) are indexed metadata only — for those the
/// indexer stores an empty body once and moves on.
const bodyIndexableFormats = {
  DocFormat.pdf,
  DocFormat.epub,
  DocFormat.txt,
  DocFormat.docx,
  DocFormat.odt,
  DocFormat.rtf,
  DocFormat.pptx,
  DocFormat.xlsx,
};

/// Extract the searchable body text of a stored document.
///
/// Anything can fail here (corrupt zip, truncated pdfium text) — the caller
/// treats '' as "no body" and never rethrows.
Future<String> extractBodyText(String path, DocFormat format) async {
  try {
    switch (format) {
      case DocFormat.txt:
        final bytes = await File(path).readAsBytes();
        return _cap(utf8.decode(bytes, allowMalformed: true));
      case DocFormat.pdf:
        return _cap(await _pdf(path));
      case DocFormat.epub:
        return _cap(await _epub(path));
      case DocFormat.docx:
        final bytes = await File(path).readAsBytes();
        return _cap(_joinDocx(bytes));
      case DocFormat.odt:
        final bytes = await File(path).readAsBytes();
        return _cap(joinOdt(bytes));
      case DocFormat.rtf:
        final bytes = await File(path).readAsBytes();
        return _cap(extractRtfText(String.fromCharCodes(bytes)));
      case DocFormat.pptx:
        final bytes = await File(path).readAsBytes();
        return _cap(_joinPptx(bytes));
      case DocFormat.xlsx:
        final bytes = await File(path).readAsBytes();
        return _cap(await _joinXlsx(bytes));
      case _:
        return '';
    }
  } on Object {
    return '';
  }
}

// --- format-specific ---------------------------------------------------------

Future<String> _pdf(String path) async {
  final doc = await pdfrx.PdfDocument.openFile(path);
  try {
    final buf = StringBuffer();
    final pageCount = doc.pages.length;
    for (var i = 0; i < pageCount && i < _maxPdfPages; i++) {
      final text = await doc.pages[i].loadText();
      if (text != null && text.fullText.isNotEmpty) {
        buf.writeln(text.fullText);
      }
    }
    return buf.toString();
  } finally {
    try {
      await doc.dispose();
    } catch (_) {}
  }
}

String _joinDocx(List<int> bytes) =>
    extractDocxParagraphs(Uint8List.fromList(bytes))
        .map((p) => p.text)
        .join('\n');

String joinOdt(List<int> bytes) => extractOdtParagraphs(Uint8List.fromList(bytes))
    .map((p) => p.text)
    .join('\n');

String _joinPptx(List<int> bytes) {
  final slides = extractPptxSlides(Uint8List.fromList(bytes));
  return [
    for (final s in slides)
      s.body.isEmpty
          ? s.title
          : s.title.isEmpty
              ? s.body.join(' — ')
              : '${s.title} — ${s.body.join(' — ')}',
  ].where((t) => t.isNotEmpty).join('\n');
}

Future<String> _joinXlsx(List<int> bytes) async {
  final excel = await Excel.decodeBytesAsync(bytes);
  final buf = StringBuffer();
  for (final name in excel.tables.keys) {
    buf.writeln(name);
    for (final row in excel[name].rows.take(5000)) {
      final cells = [
        for (final cell in row)
          if ((cell?.displayText ?? '').trim().isNotEmpty)
            cell!.displayText.trim(),
      ];
      if (cells.isNotEmpty) buf.writeln(cells.join(' · '));
    }
  }
  return buf.toString();
}

/// EPUB body: container.xml → OPF → spine order → text/html items merged.
Future<String> _epub(String path) async {
  final zip = ZipDecoder().decodeBytes(
    await File(path).readAsBytes(),
    verify: false,
  );

  final container = zip.findFile('META-INF/container.xml');
  if (container == null) return '';
  final containerDoc =
      XmlDocument.parse(String.fromCharCodes(container.content as List<int>));
  final opfPath = containerDoc
          .findAllElements('rootfile')
          .firstOrNull
          ?.getAttribute('full-path') ??
      '';
  if (opfPath.isEmpty) return '';

  final opf = zip.findFile(opfPath);
  if (opf == null) return '';
  final opfDoc = XmlDocument.parse(String.fromCharCodes(opf.content as List<int>));

  final manifest = <String, XmlElement>{
    for (final item in opfDoc.findAllElements('item', namespaceUri: '*'))
      item.getAttribute('id') ?? '': item,
  };

  final opfDir = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/'))
      : '';
  String entryPath(String href) => href.isEmpty
      ? href
      : opfDir.isEmpty
          ? Uri.decodeComponent(href)
          : '$opfDir/${Uri.decodeComponent(href)}';

  final buf = StringBuffer();
  for (final ref in opfDoc.findAllElements('itemref', namespaceUri: '*')) {
    final item = manifest[ref.getAttribute('idref')];
    if (item == null) continue;
    final mediaType = (item.getAttribute('media-type') ?? '').toLowerCase();
    if (!(mediaType.contains('html'))) continue;
    final entry =
        zip.findFile(entryPath(item.getAttribute('href') ?? ''));
    if (entry == null) continue;
    final html = utf8.decode(
      entry.content as List<int>,
      allowMalformed: true,
    );
    final text = stripHtmlText(html);
    if (text.isNotEmpty) buf.writeln(text);
  }
  return buf.toString();
}

// --- shared helpers ----------------------------------------------------------

/// Strip an HTML/XHTML fragment down to words. script/style/head subtrees
/// are dropped; entity decoding is best-effort numeric + common named.
String stripHtmlText(String html) {
  var s = html;
  s = s.replaceAll(
      RegExp(r'<(script|style|head)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
      ' ');
  s = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
  s = decodeEntities(s);
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

final _namedEntities = <String, String>{
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&nbsp;': ' ',
};

String decodeEntities(String s) {
  for (final e in _namedEntities.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? '' : String.fromCharCode(code);
  });
  s = s.replaceAllMapped(RegExp('&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code == null ? '' : String.fromCharCode(code);
  });
  return s;
}

String _cap(String text) {
  final trimmed = text.trim();
  if (trimmed.length <= _maxBodyChars) return trimmed;
  return trimmed.substring(0, _maxBodyChars);
}
