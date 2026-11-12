import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docview/features/dictionary/data/dict_zip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a real dictzip-format file: FEXTRA 'RA' header + one gzip member
/// per chunk (mirrors the dictzip CLI output that dict.js/StarDict reads).
Uint8List buildDictZip(List<List<int>> chunks) {
  final out = BytesBuilder();
  final header = BytesBuilder();
  header.add([0x1f, 0x8b, 0x08, 0x04]); // gzip + FEXTRA
  header.add([0, 0, 0, 0, 0, 0]); // mtime/xfl/os
  final chlen = 1024;
  final compressed = [for (final chunk in chunks) gzip.encode(chunk)];
  final extra = BytesBuilder();
  extra.add([0x52, 0x41]); // 'RA' — subfield ID
  final dataLen = 6 + 2 * compressed.length;
  extra.add([dataLen & 0xff, (dataLen >> 8) & 0xff]); // SLEN
  extra.add([0x01, 0x00]); // version 1
  extra.add([
    chlen & 0xff,
    (chlen >> 8) & 0xff,
    compressed.length & 0xff,
    (compressed.length >> 8) & 0xff,
  ]);
  // Chunk sizes in the table are COMPRESSED sizes (dictzip format).
  for (final gz in compressed) {
    extra.add([gz.length & 0xff, (gz.length >> 8) & 0xff]);
  }
  final extraBytes = extra.toBytes();
  header.add([(extraBytes.length) & 0xff, ((extraBytes.length) >> 8) & 0xff]);
  header.add(extraBytes);
  out.add(header.toBytes());
  for (final gz in compressed) {
    out.add(gz);
  }
  return out.toBytes();
}

void main() {
  group('dictZipChunkTable + inflateDictZip', () {
    test('round-trips small text through synthetic dictzip', () {
      const text = 'Battery test page one. Hello DocView!';
      final chunks = [utf8.encode(text)];
      final dz = buildDictZip(chunks);

      final table = dictZipChunkTable(dz);
      expect(table, hasLength(1));
      // Table entries record the COMPRESSED chunk size.
      expect(table[0].$2, gzip.encode(utf8.encode(text)).length);

      final flat = inflateDictZip(dz);
      expect(utf8.decode(flat), text);
    });

    test('handles multiple chunks with correct offsets', () {
      final chunks = [
        utf8.encode('apple — a fruit.'),
        utf8.encode('battery — a device.'),
        utf8.encode('cider — a drink.'),
      ];
      final dz = buildDictZip(chunks);
      final flat = inflateDictZip(dz);
      expect(
        utf8.decode(flat),
        'apple — a fruit.battery — a device.cider — a drink.',
      );
    });

    test('rejects non-gzip data', () {
      final bad = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      expect(() => dictZipChunkTable(bad), throwsA(isA<DictZipFormatException>()));
    });

    test('rejects gzip without FEXTRA', () {
      final plainGzip = Uint8List.fromList(gzip.encode(utf8.encode('hello')));
      // FLG=0 in a plain gzip encode → missing FEXTRA.
      expect(
        () => dictZipChunkTable(plainGzip),
        throwsA(isA<DictZipFormatException>()),
      );
    });
  });

  group('StarDictIfo', () {
    test('parses fields', () {
      final ifo = StarDictIfo.parse('StarDict\'s dict ifo file version=2.4.2\n'
          'wordcount=3\n'
          'bookname=Test Dict\n'
          'sametypesequence=m\n');
      expect(ifo.bookName, 'Test Dict');
      expect(ifo.sametypesequence, 'm');
      expect(ifo.wordCount, '3');
    });

    test('throws without bookname', () {
      expect(
        () => StarDictIfo.parse('version=2.4.2\nwordcount=1\n'),
        throwsA(isA<DictZipFormatException>()),
      );
    });
  });

  group('decodeStarDictArticle', () {
    test('plain m-type stays as-is', () {
      final out = decodeStarDictArticle(
        Uint8List.fromList(utf8.encode('A device producing current.')),
        'm',
      );
      expect(out, 'A device producing current.');
    });

    test('h-type strips html and resolves entities', () {
      final out = decodeStarDictArticle(
        Uint8List.fromList(utf8.encode(
            '<div><b>Battery</b>: a &amp; b</div><style>x</style>')),
        'h',
      );
      expect(out, 'Battery: a & b');
    });
  });
}
