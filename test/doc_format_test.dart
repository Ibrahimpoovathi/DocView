import 'package:docview/core/format/doc_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocFormat.detect', () {
    test('maps extensions', () {
      expect(DocFormat.detect('book.pdf'), DocFormat.pdf);
      expect(DocFormat.detect('BOOK.EPUB'), DocFormat.epub);
      expect(DocFormat.detect('résumé.docx'), DocFormat.docx);
      expect(DocFormat.detect('notes.md'), DocFormat.txt);
      expect(DocFormat.detect('comic.cbz'), DocFormat.cbz);
      expect(DocFormat.detect('novel.mobi'), DocFormat.mobi);
      expect(DocFormat.detect('novel.prc'), DocFormat.mobi);
      expect(DocFormat.detect('kindle.azw3'), DocFormat.azw3);
      expect(DocFormat.detect('fb.fb2'), DocFormat.fb2);
      expect(DocFormat.detect('data.xlsx'), DocFormat.xlsx);
      expect(DocFormat.detect('report.rtf'), DocFormat.rtf);
      expect(DocFormat.detect('unknown.xyz'), DocFormat.other);
      expect(DocFormat.detect('noextension'), DocFormat.other);
    });

    test('magic head refines epub', () {
      // [Content_Types]-style zip but with EPUB mimetype first.
      final head = [0x50, 0x4B, 0x03, 0x04, ...'application/epub+zip'.codeUnits];
      expect(DocFormat.detect('weird.zip', magicHead: head), DocFormat.epub);
    });

    test('magic head catches pdf', () {
      final head = [...'%PDF-1.7'.codeUnits];
      expect(DocFormat.detect('renamed.bin', magicHead: head), DocFormat.pdf);
    });

    test('magic head catches mobi', () {
      final head = List<int>.filled(72, 0);
      final bookmobi = 'BOOKMOBI'.codeUnits;
      for (var i = 0; i < 8; i++) {
        head[60 + i] = bookmobi[i];
      }
      expect(DocFormat.detect('renamed.bin', magicHead: head), DocFormat.mobi);
    });

    test('plain text with no matching magic keeps extension guess', () {
      expect(
        DocFormat.detect('note.txt', magicHead: List<int>.filled(16, 0x41)),
        DocFormat.txt,
      );
    });
  });
}
