/// DictZip (.dict.dz) → plain .dict conversion, done at import time.
///
/// DictZip is gzip with a FEXTRA 'RA' header listing chunk sizes; every
/// chunk is a standalone gzip member, so chunk-wise `gzip.decode`
/// reassembles the original bytes. Decompressed offsets are identical to
/// the ones in the .idx (dictzip preserves length information), so the
/// StarDict index stays valid against the plain output.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DictZipFormatException implements Exception {
  DictZipFormatException(this.message);
  final String message;

  @override
  String toString() => 'DictZipFormatException: $message';
}

/// Parses the dictzip header and returns the chunk table
/// (compressed offset + compressed length per chunk).
List<(int, int)> dictZipChunkTable(Uint8List bytes) {
  if (bytes.length < 12) throw DictZipFormatException('file too short');
  if (bytes[0] != 0x1f || bytes[1] != 0x8b || bytes[2] != 8) {
    throw DictZipFormatException('not a gzip file');
  }
  final flg = bytes[3];
  if (flg & 0x04 == 0) throw DictZipFormatException('missing FEXTRA');
  final xlen = bytes[10] | (bytes[11] << 8);
  if (xlen < 6 || 12 + xlen > bytes.length) {
    throw DictZipFormatException('bad FEXTRA length');
  }
  final extra = ByteData.sublistView(bytes, 12, 12 + xlen);
  if (extra.getUint8(0) != 0x52 || extra.getUint8(1) != 0x41) {
    throw DictZipFormatException('FEXTRA subfield is not RA');
  }
  if (extra.getUint16(4, Endian.little) != 1) {
    throw DictZipFormatException('unsupported dictzip version');
  }
  final chlen = extra.getUint16(6, Endian.little);
  final chcnt = extra.getUint16(8, Endian.little);
  if (chlen == 0 || chcnt == 0) throw DictZipFormatException('bad chunk table');

  var offset = 12 + xlen;
  // Optional header fields after FEXTRA (dictzip writes none of these).
  if (flg & 0x08 != 0) {
    final nul = bytes.indexOf(0, offset);
    if (nul < 0) throw DictZipFormatException('bad FNAME');
    offset = nul + 1;
  }
  if (flg & 0x10 != 0) {
    final nul = bytes.indexOf(0, offset);
    if (nul < 0) throw DictZipFormatException('bad FCOMMENT');
    offset = nul + 1;
  }
  if (flg & 0x02 != 0) offset += 2; // FHCRC

  final chunks = <(int, int)>[];
  var compressed = 0;
  for (var i = 0; i < chcnt; i++) {
    final size = extra.getUint16(10 + 2 * i, Endian.little);
    chunks.add((compressed, size));
    compressed += size;
  }
  if (offset + compressed > bytes.length) {
    throw DictZipFormatException('truncated compressed data');
  }
  return chunks;
}

/// Decompresses a .dict.dz into the original dictionary bytes.
Uint8List inflateDictZip(Uint8List bytes) {
  final chunks = dictZipChunkTable(bytes);
  final headerLen = _compressedDataStart(bytes);
  final out = BytesBuilder();
  for (final (offset, size) in chunks) {
    final member = Uint8List.sublistView(
        bytes, headerLen + offset, headerLen + offset + size);
    out.add(gzip.decode(member));
  }
  return out.toBytes();
}

int _compressedDataStart(Uint8List bytes) {
  final flg = bytes[3];
  var offset = 12 + (bytes[10] | (bytes[11] << 8));
  if (flg & 0x08 != 0) offset = bytes.indexOf(0, offset) + 1;
  if (flg & 0x10 != 0) offset = bytes.indexOf(0, offset) + 1;
  if (flg & 0x02 != 0) offset += 2;
  return offset;
}

/// StarDict .ifo content (subset we need).
class StarDictIfo {
  StarDictIfo({required this.fields});

  factory StarDictIfo.parse(String content) {
    final fields = <String, String>{};
    for (final line in content.split('\n')) {
      final sep = line.indexOf('=');
      if (sep <= 0) continue;
      fields[line.substring(0, sep)] = line.substring(sep + 1);
    }
    if (!fields.containsKey('bookname')) {
      throw DictZipFormatException('ifo missing bookname');
    }
    return StarDictIfo(fields: fields);
  }

  final Map<String, String> fields;

  String get bookName => fields['bookname']!;
  String get sametypesequence => fields['sametypesequence'] ?? 'm';
  String get wordCount => fields['wordcount'] ?? '';
  String get sameWordSequence => fields['samewordsequence'] ?? '';
}

/// Decodes one StarDict article payload (`data` from the .dict file) into
/// displayable text according to `sametypesequence`.
String decodeStarDictArticle(Uint8List data, String seq) {
  final text = utf8.decode(data, allowMalformed: true);
  switch (seq) {
    case 'h': // HTML
    case 'x': // xdxf markup
      return _stripHtml(text);
    default: // 'm' plain, 'l'/'g'/'t'/'y' — treat as plain text
      return text;
  }
}

String _stripHtml(String html) => html
    .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .trim();
