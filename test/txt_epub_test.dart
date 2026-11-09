
import 'package:archive/archive.dart';
import 'package:docview/features/reader/data/txt_to_epub.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('txtToEpub produces a zip-readable EPUB with chapters', () {
    final buf = StringBuffer();
    for (var ch = 1; ch <= 3; ch++) {
      buf.writeln('Chapter $ch');
      for (var i = 1; i <= 30; i++) {
        buf.writeln('Paragraph $i with plenty of words to fill the page.');
      }
    }
    final epub = txtToEpub(
        Uint8List.fromList(buf.toString().codeUnits));
    final archive = ZipDecoder()
        .decodeBytes(epub)
        .files
        .where((f) => f.isFile)
        .toList();

    final names = archive.map((f) => f.name).toSet();
    expect(names, contains('mimetype'));
    expect(names, contains('META-INF/container.xml'));
    expect(names, contains('OEBPS/content.opf'));
    expect(names, contains('OEBPS/nav.xhtml'));
    expect(archive.where((f) => f.name.startsWith('OEBPS/ch')).length,
        greaterThanOrEqualTo(1));

    // mimetype content survives round-trip
    final mimetype =
        archive.firstWhere((f) => f.name == 'mimetype').content as List<int>;
    expect(mimetype, 'application/epub+zip'.codeUnits);
  });

  test('txtToEpub is deterministic and produces valid container bytes',
      () {
    final a =
        txtToEpub(Uint8List.fromList('Hello world'.codeUnits));
    final b =
        txtToEpub(Uint8List.fromList('Hello world'.codeUnits));
    expect(a, isA<Uint8List>());
    // EPUB alive: decode both, compare logical file sets
    final an = ZipDecoder().decodeBytes(a).files.map((f) => f.name).toSet();
    final bn = ZipDecoder().decodeBytes(b).files.map((f) => f.name).toSet();
    expect(an, bn);
  });
}
