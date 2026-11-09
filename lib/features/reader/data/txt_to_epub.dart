import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

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
  for (var i = 0; i < sections.length; i++) {
    final body = sections[i].map(escape).map((t) => '<p>$t</p>').join('\n');
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

  if (sections.isEmpty) {
    add(
      'OEBPS/ch1.xhtml',
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p></p></body></html>',
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
