import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Minimal one-page EPUB shown when a text file exceeds the conversion size
/// cap — renders as a normal reader page instead of an error banner.
Uint8List txtTooLargeEpub(int sizeBytes) =>
    _tooLargeEpub(sizeBytes, 'text', maxTxtConvertMb);

/// Same friendly page for oversized FB2 books.
Uint8List fb2TooLargeEpub(int sizeBytes) =>
    _tooLargeEpub(sizeBytes, 'FB2', maxFb2ConvertMb);

Uint8List _tooLargeEpub(int sizeBytes, String kind, int capMb) {
  final mb = (sizeBytes / (1024 * 1024)).toStringAsFixed(0);
  final page = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta charset="utf-8"/><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
<p>This $kind file is $mb MB. DocView opens $kind files up to
$capMb MB so the reader stays fast.</p>
</body>
</html>''';
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip')
      ..compression = CompressionType.none)
    ..addFile(ArchiveFile.string(
        'META-INF/container.xml', _containerXml))
    ..addFile(ArchiveFile.string('OEBPS/content.opf', _opf))
    ..addFile(ArchiveFile.string('OEBPS/ch1.xhtml', page));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Cap in MB for on-the-fly txt→EPUB conversion (shared with book_server).
const maxTxtConvertMb = 15;

/// Cap in MB for on-the-fly fb2→EPUB conversion (shared with book_server).
const maxFb2ConvertMb = 15;

const _containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

const _opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:docview-txt-large</dc:identifier>
    <dc:title>Text (too large)</dc:title>
    <dc:language>und</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>''';

/// Wraps plain text documents in a minimal EPUB 3 so foliate-js can render
/// them with the same paginator as real EPUBs (chunked xhtml sections).
Uint8List txtToEpub(Uint8List bytes) {
  final text =
      utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n');

  // Chunk into paragraph-preserving sections (~12k chars each).
  final paragraphs = text.split(RegExp(r'\n{2,}'));
  final sections = <List<String>>[[]];
  var len = 0;
  for (final para in paragraphs) {
    if (para.isEmpty) continue;
    final n = para.length;
    if (len + n > 12000 && sections.last.isNotEmpty) {
      sections.add([para]);
      len = n;
    } else {
      sections.last.add(para);
      len += n;
    }
  }
  // Empty / whitespace-only input: keep a single placeholder section so the
  // nav/spine loops below always have at least one entry.
  if (sections.last.isEmpty) sections.last.add('');

  String escape(String t) => t
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

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
  final opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:docview-txt-${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
    <dc:title>Text</dc:title>
    <dc:language>und</dc:language>
  </metadata>
  <manifest>
    $manifestItems  </manifest>
  <spine>
    $spineRefs  </spine>
</package>''';

  final navEntries = StringBuffer();
  for (var i = 0; i < sections.length; i++) {
    final label = sections[i].first.replaceAll('\n', ' ').trim();
    final truncated =
        label.length > 48 ? '${label.substring(0, 48)}…' : label;
    navEntries.write('<li><a href="ch${i + 1}.xhtml">$truncated</a></li>\n');
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
p { margin: 0.8em 0; text-align: start; white-space: pre-wrap; }
h1 { font-size: 1.1em; }
''';

  final archive = Archive();
  // mimetype must be FIRST and STORED per EPUB spec.
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
  for (var i = 0; i < sections.length; i++) {    final body = sections[i].map(escape).map((t) => '<p>$t</p>').join('\n');
    add(
      'OEBPS/ch${i + 1}.xhtml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta charset="utf-8"/><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
$body
</body>
</html>''',
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
