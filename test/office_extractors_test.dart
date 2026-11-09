import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docview/features/reader/data/odt_text.dart';
import 'package:docview/features/reader/data/pptx_text.dart';
import 'package:docview/features/reader/data/rtf_text.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveFile _stored(String name, List<int> bytes) =>
    ArchiveFile.bytes(name, Uint8List.fromList(bytes))
      ..compression = CompressionType.none;

Uint8List _ooxmlZip(Map<String, String> xmls) {
  final archive = Archive();
  for (final e in xmls.entries) {
    archive.addFile(_stored(e.key, utf8.encode(e.value)));
  }
  final zip = ZipEncoder().encode(archive);
  return Uint8List.fromList(zip);
}
void main() {
  group('rtf_text', () {
    test('plain paragraphs and escapes', () {
      const rtf = r"{\ansi Hello \'e9\u10084?\par Second \tab line.";
      final text = extractRtfText(rtf);
      expect(text, contains('Hello é'));
      expect(text, contains('\u2764'));
      expect(text.split('\n').length, greaterThanOrEqualTo(2));
      expect(text.contains('\\'), isFalse);
    });

    test('skips destination groups and format tables', () {
      const rtf = r'{\rtf1\ansi{\fonttbl{\f0 Times New Roman;}}'
          r'{\*\fldinst{HIDDEN]];}}Body{\*\generator Fake.} text end';
      final text = extractRtfText(rtf);
      expect(text, contains('Body text end'));
      expect(text, isNot(contains('HIDDEN')));
      expect(text, isNot(contains('Times')));
      expect(text, isNot(contains('Fake')));
    });

    test('cyrillic via \\u with positive value', () {
      const rtf = r'{\rtf1\u1055?ru}';
      expect(extractRtfText(rtf), contains('Пru'));
    });

    test('braces escapes pass through', () {
      const rtf = r'{\rtf1 \{mixed\} braces}';
      expect(extractRtfText(rtf), contains('{mixed} braces'));
    });
  });

  group('odt_text', () {
    test('extracts headings and paragraphs in order', () {
      const content = '''
<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:automatic-styles><style /></office:automatic-styles>
  <office:body><office:text>
    <text:h>Chapter One</text:h>
    <text:p>First paragraph.</text:p>
    <text:list><text:list-item><text:p>nested item</text:p></text:list-item></text:list>
    <text:p></text:p>
  </office:text></office:body>
</office:document-content>
''';
      final zip = _ooxmlZip({
        'mimetype': 'application/vnd.oasis.opendocument.text',
        'content.xml': content,
      });
      final pars = extractOdtParagraphs(zip);
      expect(pars.map((p) => p.text).toList(),
          ['Chapter One', 'First paragraph.', 'nested item']);
      expect(pars.first.isHeading, isTrue);
      expect(pars[1].isHeading, isFalse);
    });

    test('missing content.xml throws', () {
      final zip = _ooxmlZip({'mimetype': 'application/vnd.core'});
      expect(() => extractOdtParagraphs(zip), throwsFormatException);
    });
  });

  group('pptx_text', () {
    const xmlDocWrap = '''<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="urn:p" xmlns:a="urn:a">
  <p:cSld><p:spTree>
    <p:sp><p:txBody><a:p><a:r><a:t>TITLE</a:t></a:r></a:p></p:txBody></p:sp>
    <p:sp><p:txBody><a:p><a:r><a:t>BODY</a:t></a:r></a:p></p:txBody></p:sp>
  </p:spTree></p:cSld>
</p:sld>''';

    test('slides sorted by real number regardless of zip order', () {
      final zip = _ooxmlZip({
        'ppt/slides/slide10.xml':
            xmlDocWrap.replaceAll('TITLE', 'Big').replaceAll('BODY', 'Deck'),
        'ppt/slides/slide2.xml':
            xmlDocWrap.replaceAll('TITLE', 'Second').replaceAll('BODY', 'B2'),
        'ppt/slides/slide1.xml':
            xmlDocWrap.replaceAll('TITLE', 'First').replaceAll('BODY', 'B1'),
      });
      final slides = extractPptxSlides(zip);
      expect(slides.map((s) => s.number).toList(), [1, 2, 10]);
      expect(slides.first.title, 'First');
      expect(slides.first.body, ['B1']);
    });

    test('skips empty slides and throws when no text', () {
      final emptyZip = _ooxmlZip({
        'ppt/slides/slide1.xml': '<p:sld xmlns:p="urn:p" xmlns:a="urn:a"/>',
      });
      expect(() => extractPptxSlides(emptyZip), throwsFormatException);
    });
  });
}
