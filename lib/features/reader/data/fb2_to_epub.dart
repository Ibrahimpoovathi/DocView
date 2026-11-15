import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Converts FictionBook 2 (fb2) XML into a minimal EPUB 3 so the reflow
/// reader renders it through the same stable EPUB pipeline as real EPUBs.
/// Replaces foliate-js's in-renderer fb2.js path, which crashed the WebView
/// renderer under audit (aw_browser_terminator code -1 → blank screen).
///
/// Covers the core fb2 subset: bodies/sections/titles, p/poem/cite/epigraph/
/// subtitle, empty-line, inline styling (strong/emphasis/style/strike/sub/
/// sup/code/anchors), tables, and base64 `binary` images (embedded as data
/// URIs). Unknown elements render as blocks with their text preserved.
Uint8List fb2ToEpub(Uint8List bytes) {
  final xml = XmlDocument.parse(_decodeFb2(bytes));
  final root = xml.rootElement;

  // --- embedded binaries (base64 images) → data URIs ------------------------
  final binaries = <String, String>{};
  for (final bin in root.findAllElements('binary')) {
    final id = bin.getAttribute('id');
    final type = bin.getAttribute('content-type') ?? 'image/jpeg';
    final data = bin.innerText.replaceAll(RegExp(r'\s'), '');
    if (id != null && data.isNotEmpty) {
      binaries[id] = 'data:$type;base64,$data';
    }
  }

  // --- metadata --------------------------------------------------------------
  String textOf(XmlNode? node) =>
      node == null ? '' : node.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
  final titleInfo = root.findAllElements('title-info').isEmpty
      ? null
      : root.findAllElements('title-info').first;
  final bookTitle = titleInfo == null
      ? 'Untitled'
      : textOf(titleInfo.getElement('book-title'));
  final authors = (titleInfo?.findElements('author').toList() ?? const [])
      .map((a) => [
            a.getElement('first-name')?.innerText,
            a.getElement('middle-name')?.innerText,
            a.getElement('last-name')?.innerText,
            a.getElement('nickname')?.innerText,
          ]
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim())
      .where((s) => s.isNotEmpty)
      .join(', ');
  final language = titleInfo == null
      ? 'und'
      : (textOf(titleInfo.getElement('lang')).isEmpty
          ? 'und'
          : textOf(titleInfo.getElement('lang')));

  // --- section blocks ---------------------------------------------------------
  // Each block is a chunk of XHTML; sections pack blocks up to 12k chars.
  final blocks = <({String label, String html})>[];

  String inline(XmlNode node) {
    if (node is XmlText) return _escape(node.value);
    if (node is XmlCDATA) return _escape(node.value);
    if (node is! XmlElement) return '';
    switch (node.name.local) {
      case 'strong':
        return '<strong>${_children(node, inline)}</strong>';
      case 'emphasis':
        return '<em>${_children(node, inline)}</em>';
      case 'style':
        return '<span>${_children(node, inline)}</span>';
      case 'strikethrough':
        return '<s>${_children(node, inline)}</s>';
      case 'sub':
        return '<sub>${_children(node, inline)}</sub>';
      case 'sup':
        return '<sup>${_children(node, inline)}</sup>';
      case 'code':
        return '<code>${_children(node, inline)}</code>';
      case 'a':
        final href =
            node.getAttribute('href') ?? node.getAttribute('l:href') ?? '';
        final clean = href.startsWith('#') ? '' : href;
        return '<a${clean.isEmpty ? '' : ' href="${_escapeAttr(clean)}"'}'
            '>${_children(node, inline)}</a>';
      case 'image':
        final href =
            node.getAttribute('l:href') ?? node.getAttribute('href') ?? '';
        final src = href.startsWith('#')
            ? binaries[href.substring(1)] ?? ''
            : href;
        return '<img src="${_escapeAttr(src)}" alt=""/>';
      default:
        return _children(node, inline);
    }
  }

  String block(XmlElement el) {
    switch (el.name.local) {
      case 'p':
        final content = _children(el, inline);
        return content.isEmpty ? '' : '<p>$content</p>';
      case 'empty-line':
        return '<br/>';
      case 'v':
        final content = _children(el, inline);
        return content.isEmpty ? '' : '$content<br/>';
      case 'image':
        final img = inline(el);
        return img.isEmpty ? '' : '<p class="img">$img</p>';
      case 'subtitle':
        return '<h3>${_children(el, inline)}</h3>';
      case 'text-author':
        return '<p class="author">${_children(el, inline)}</p>';
      case 'date':
        return '<p class="author">${_children(el, inline)}</p>';
      case 'epigraph':
        return '<blockquote class="epigraph">${_blockChildren(el, block)}</blockquote>';
      case 'cite':
        return '<blockquote>${_blockChildren(el, block)}</blockquote>';
      case 'poem':
        return '<div class="poem">${_blockChildren(el, block)}</div>';
      case 'stanza':
        return '<div class="stanza">${_blockChildren(el, block)}</div>';
      case 'table':
        final rows = <String>[];
        for (final tr in el.findElements('tr')) {
          final cells = <String>[];
          for (final cell
              in [...tr.findElements('th'), ...tr.findElements('td')]) {
            cells.add('<td>${_children(cell, inline)}</td>');
          }
          rows.add('<tr>${cells.join()}</tr>');
        }
        return '<table>${rows.join()}</table>';
      case 'title':
        // Caller handles titles (used for the TOC label).
        return '';
      default:
        // Unknown element: keep its content so nothing silently drops.
        final inner = _children(el, inline);
        return inner.isEmpty ? '' : '<p>$inner</p>';
    }
  }

  /// Renders a `<title>` inside a section: each p becomes a heading line.
  String titleHtml(XmlElement title, {required bool isBookTitle}) {
    final lines = title.findElements('p').map((p) => textOf(p)).toList();
    final tag = isBookTitle ? 'h1' : 'h2';
    return lines
        .where((l) => l.isNotEmpty)
        .map((l) => '<$tag>${_escape(l)}</$tag>')
        .join();
  }

  final bodies = root.findAllElements('body').toList();
    for (var bi = 0; bi < bodies.length; bi++) {
    final body = bodies[bi];
    for (final child in body.childElements) {
      if (child.name.local == 'title') {
        final html = titleHtml(child, isBookTitle: bi == 0);
        if (html.isNotEmpty) {
          blocks.add((label: textOf(child), html: html));
        }
      } else if (child.name.local == 'section') {
        final title = child.getElement('title');
        final label = textOf(title ?? child);
        final sectionHtml =
            StringBuffer(title == null ? '' : titleHtml(title, isBookTitle: false));
        for (final el in child.childElements) {
          if (el.name.local == 'title') continue;
          final html = block(el);
          if (html.isNotEmpty) sectionHtml.write(html);
        }
        if (sectionHtml.isEmpty) sectionHtml.write('<p></p>');
        blocks.add((label: label, html: sectionHtml.toString()));
      } else {
        final html = block(child);
        if (html.isNotEmpty) blocks.add((label: '', html: html));
      }
    }
  }
  if (blocks.isEmpty) blocks.add((label: '', html: '<p></p>'));

  // --- pack blocks into ~12k-char xhtml sections ------------------------------
  // A labeled block (fb2 section title) starts a fresh chunk so the TOC keeps
  // per-section entries; oversized sections still split mid-body.
  final sections = <({String label, String body})>[];
  var current = StringBuffer();
  var currentLabel = '';
  var currentLen = 0;
  for (final b in blocks) {
    final split = currentLen > 0 && currentLen + b.html.length > 12000;
    final heading = currentLen > 0 &&
        b.label.isNotEmpty &&
        currentLabel.isNotEmpty;
    if (split || heading) {
      sections.add((label: currentLabel, body: current.toString()));
      current = StringBuffer();
      currentLen = 0;
    }
    if (currentLen == 0) currentLabel = b.label;
    current.write(b.html);
    currentLen += b.html.length;
  }
  sections.add((label: currentLabel, body: current.toString()));

  // --- assemble the EPUB ------------------------------------------------------
  final containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

  final manifestItems = StringBuffer(
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n'
    '<item id="css" href="style.css" media-type="text/css"/>\n',
  );
  final spineRefs = StringBuffer();
  for (var i = 0; i < sections.length; i++) {
    manifestItems.write(
      '<item id="ch${i + 1}" href="ch${i + 1}.xhtml" media-type="application/xhtml+xml"/>\n',
    );
    spineRefs.write('<itemref idref="ch${i + 1}"/>\n');
  }
  final authorMeta =
      authors.isEmpty ? '' : '<dc:creator>${_escapeAttr(authors)}</dc:creator>';
  final opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:docview-fb2-${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
    <dc:title>${_escapeAttr(bookTitle)}</dc:title>
    $authorMeta
    <dc:language>${_escapeAttr(language)}</dc:language>
  </metadata>
  <manifest>
    $manifestItems  </manifest>
  <spine>
    $spineRefs  </spine>
</package>''';

  final navEntries = StringBuffer();
  for (var i = 0; i < sections.length; i++) {
    final label = sections[i].label.isEmpty
        ? 'Section ${i + 1}'
        : sections[i].label;
    final truncated = label.length > 48 ? '${label.substring(0, 48)}…' : label;
    navEntries.write(
        '<li><a href="ch${i + 1}.xhtml">${_escape(truncated)}</a></li>\n');
  }
  final nav = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><meta charset="utf-8"/><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol>
$navEntries</ol></nav></body>
</html>''';

  final css = '''
html, body { margin: 0; padding: 0; }
body { line-height: 1.6; padding: 1em; }
p { margin: 0.8em 0; }
h1 { font-size: 1.4em; text-align: center; }
h2 { font-size: 1.2em; margin: 1.2em 0 0.6em; }
h3 { font-size: 1.05em; }
blockquote { margin: 1em 1.5em; }
.poem { margin: 1em 2em; }
.stanza { margin: 0.6em 0; }
p.author { text-align: end; }
p.author:before { content: "—"; }
p.img { text-align: center; }
img { max-width: 100%; }
table { border-collapse: collapse; }
td, th { padding: 0.25em; border: 1px solid #999; }
''';

  final archive = Archive();
  final mimetypeBytes = utf8.encode('application/epub+zip');
  archive.addFile(
    ArchiveFile('mimetype', mimetypeBytes.length, mimetypeBytes)
      ..compression = CompressionType.none,
  );

  void add(String path, String content) {
    final data = utf8.encode(content);
    archive.addFile(ArchiveFile(path, data.length, data));
  }

  add('META-INF/container.xml', containerXml);
  add('OEBPS/content.opf', opf);
  add('OEBPS/nav.xhtml', nav);
  add('OEBPS/style.css', css);
  for (var i = 0; i < sections.length; i++) {
    add(
      'OEBPS/ch${i + 1}.xhtml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta charset="utf-8"/><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
${sections[i].body}
</body>
</html>''',
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _children(XmlElement node, String Function(XmlNode) fn) =>
    node.children.map(fn).join();

/// Block containers hold elements separated by whitespace text; only the
/// element children carry content in block mode.
String _blockChildren(XmlElement node, String Function(XmlElement) fn) =>
    node.childElements.map(fn).join();

String _escape(String t) => t
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttr(String t) => _escape(t)
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// FB2 files in the wild are UTF-8, Windows-1251 (old Russian libraries) or
/// UTF-16. Decode by BOM, then XML declaration, then a UTF-8 attempt with a
/// cp1251 fallback — never silently mangling Cyrillic into replacement chars.
String _decodeFb2(Uint8List input) {
  var bytes = input;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    bytes = bytes.sublist(3);
  }
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes.sublist(2), littleEndian: false);
    }
  }
  final head = Latin1Codec(allowInvalid: true)
      .decode(bytes.sublist(0, math.min(bytes.length, 400)));
  final declared = RegExp(r'''encoding\s*=\s*["']([^"']+)["']''')
      .firstMatch(head)
      ?.group(1)
      ?.toLowerCase();
  if (declared != null) {
    if (declared == 'utf-16' || declared == 'utf-16le') {
      return _utf16(bytes, littleEndian: true);
    }
    if (declared == 'utf-16be') return _utf16(bytes, littleEndian: false);
    if (declared == 'windows-1251' ||
        declared == 'cp1251' ||
        declared == 'win-1251') {
      return _cp1251(bytes);
    }
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _cp1251(bytes);
  }
}

String _utf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

String _cp1251(Uint8List bytes) {
  final units = <int>[];
  for (final b in bytes) {
    units.add(b < 0x80 ? b : _cp1251High[b - 0x80]);
  }
  return String.fromCharCodes(units);
}

const _cp1251High = <int>[
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
  0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
  0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
  0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
  0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
  0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
  0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
  0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
  0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
  0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
  0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
  0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
];
