import 'package:archive/archive.dart';
import 'package:docview/features/reader/data/fb2_to_epub.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List epubOf(String xml) =>
      fb2ToEpub(Uint8List.fromList(xml.codeUnits));

  Archive archOf(String xml) => ZipDecoder().decodeBytes(epubOf(xml));

  String bodyOf(Archive a, String name) =>
      String.fromCharCodes(a.files.firstWhere((f) => f.name == name).content);

  test('fb2ToEpub produces a zip-readable EPUB with sections and metadata', () {
    final fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"
  xmlns:l="http://www.w3.org/1999/xlink">
  <description><title-info>
    <author><first-name>Ada</first-name><last-name>Lovelace</last-name></author>
    <book-title>Analytical Engines</book-title>
    <lang>en</lang>
  </title-info></description>
  <body>
    <title><p>Analytical Engines</p></title>
    <section><title><p>Chapter One</p></title>
      <p>The <strong>engine</strong> <emphasis>weaves</emphasis> algebra.</p>
      <empty-line/>
      <poem><stanza><v>Line one</v><v>Line two</v></stanza></poem>
    </section>
    <section><title><p>Chapter Two</p></title>
      <p><a l:href="http://example.com/">link</a> and <code>x + y</code>.</p>
      <image l:href="#pic1.png"/>
    </section>
  </body>
  <body name="notes"><section><title><p>Notes</p></title><p>Note one.</p></section></body>
  <binary id="pic1.png" content-type="image/png">aGVsbG8=</binary>
</FictionBook>''';
    final epub = epubOf(fb2);
    final archive = ZipDecoder().decodeBytes(epub);
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, containsAll(<String>[
      'mimetype',
      'META-INF/container.xml',
      'OEBPS/content.opf',
      'OEBPS/nav.xhtml',
      'OEBPS/ch1.xhtml',
    ]));
    final opf = bodyOf(archive, 'OEBPS/content.opf');
    expect(opf, contains('Analytical Engines'));
    expect(opf, contains('Lovelace'));
    final ch1 = bodyOf(archive, 'OEBPS/ch1.xhtml');
    expect(ch1, contains('<h1>Analytical Engines</h1>'));
    final ch2 = bodyOf(archive, 'OEBPS/ch2.xhtml');
    expect(ch2, contains('<h2>Chapter One</h2>'));
    expect(ch2, contains('<strong>engine</strong>'));
    expect(ch2, contains('<em>weaves</em>'));
    expect(ch2, contains('Line one<br/>'));
    final ch3 = bodyOf(archive, 'OEBPS/ch3.xhtml');
    expect(ch3, contains('<a href="http://example.com/">link</a>'));
    expect(ch3, contains('<code>x + y</code>'));
    expect(ch3, contains('src="data:image/png;base64,aGVsbG8="'));
    final nav = bodyOf(archive, 'OEBPS/nav.xhtml');
    expect(nav, contains('Chapter Two'));
    expect(nav, contains('Notes'));
    expect(archive.files.where((f) => RegExp(r'ch\d+\.xhtml$').hasMatch(f.name)),
        hasLength(4));
  });

  test('fb2ToEpub tolerates an empty body and unknown elements', () {
    final fb2 = '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        '<description><title-info><book-title>Bare</book-title></title-info></description>'
        '<body><section><custom>Weird <emphasis>bit</emphasis></custom></section></body>'
        '</FictionBook>';
    final archive = archOf(fb2);
    final ch1 = bodyOf(archive, 'OEBPS/ch1.xhtml');
    expect(ch1, contains('Weird <em>bit</em>'));
    final opf = bodyOf(archive, 'OEBPS/content.opf');
    expect(opf, contains('Bare'));
  });

  test('fb2ToEpub escapes text and splits long sections', () {
    final fb2 = StringBuffer(
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        '<description><title-info><book-title>a &amp; b &lt;c&gt;</book-title></title-info></description><body>');
    for (var i = 0; i < 900; i++) {
      fb2.write('<p>Paragraph $i about engines and the church of reason.</p>');
    }
    fb2.write('</body></FictionBook>');
    final archive = archOf(fb2.toString());
    final chapters = archive.files
        .where((f) => RegExp(r'ch\d+\.xhtml$').hasMatch(f.name))
        .length;
    expect(chapters, greaterThan(1));
    final opf = bodyOf(archive, 'OEBPS/content.opf');
    expect(opf, contains('a &amp; b &lt;c&gt;'));
  });
}
