import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One slide of an Office Open XML `.pptx` deck.
class PptxSlide {
  const PptxSlide({required this.number, required this.title, required this.body});

  final int number;
  final String title;
  final List<String> body;

  /// All lines of the slide (title included) — used by the text view.
  List<String> get lines => [if (title.isNotEmpty) title, ...body];
}

/// Extract slides from a `.pptx` byte payload.
///
/// PPTX is an Open XML package: `ppt/slides/slideN.xml` per slide with the
/// text of a shape in `<a:t>` runs. This reader only needs the text, so parse
/// those parts directly — no engine, no OLE/PDF round trip.
///
/// Returns slides ordered by their real numbering (slideN.xml order, N).
/// Bad/empty payloads throw [FormatException]-style errors from the underlying
/// zip/XML readers.
List<PptxSlide> extractPptxSlides(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = archive.files
      .where((f) => f.isFile && f.name.startsWith('ppt/slides/slide'))
      .toList();

  final numbered = <(int, ArchiveFile)>[];
  for (final f in files) {
    final match =
        RegExp(r'^ppt/slides/slide(\d+)\.xml$').firstMatch(f.name);
    if (match != null) {
      numbered.add((int.parse(match.group(1)!), f));
    }
  }
  numbered.sort((a, b) => a.$1.compareTo(b.$1));

  final slides = <PptxSlide>[];
  for (final (number, file) in numbered) {
    final doc = XmlDocument.parse(utf8Of(file));
    final runs = <String>[];
    for (final t in doc.findAllElements('t', namespaceUri: '*')) {
      final text = t.innerText.replaceAll('\n', ' ').trim();
      if (text.isNotEmpty) runs.add(text);
    }
    if (runs.isEmpty) continue;
    slides.add(PptxSlide(
      number: number,
      title: runs.first,
      body: runs.skip(1).toList(),
    ));
  }
  if (slides.isEmpty) {
    throw const FormatException('No text slides found in presentation');
  }
  return slides;
}

String utf8Of(ArchiveFile f) => utf8.decode(f.content as List<int>);
