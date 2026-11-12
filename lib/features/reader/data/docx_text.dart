import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Paragraph of a `.docx` (WordprocessingML) file: plain text with a soft
/// heading flag (matched via `w:pStyle` starting with "Heading").
class DocxParagraph {
  const DocxParagraph({required this.text, required this.isHeading});

  final String text;
  final bool isHeading;
}

/// Extract paragraphs from a `.docx` byte payload.
///
/// DOCX is a zip whose body lives in `word/document.xml` as `w:p` elements.
/// This file is only ever parsed for DOCX payloads, so elements are matched
/// by local name (`p` / `t` / `br` / `tab`) without namespace ceremony.
/// We walk document order so tables/lists stay in reading order; `w:br` and
/// `w:tab` become spaces, `w:t` runs are concatenated.
List<DocxParagraph> extractDocxParagraphs(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final content = archive.findFile('word/document.xml');
  if (content == null) {
    throw const FormatException('missing word/document.xml');
  }
  final doc = XmlDocument.parse(utf8.decode(content.content as List<int>));

  final out = <DocxParagraph>[];
  void visit(XmlElement el) {
    if (el.name.local == 'p') {
      final text = _paragraphText(el);
      if (text.isNotEmpty) {
        out.add(DocxParagraph(text: text, isHeading: _isHeading(el)));
      }
      // Do not recurse: w:p cannot nest inside w:p.
      return;
    }
    for (final child in el.childElements) {
      visit(child);
    }
  }

  visit(doc.rootElement);
  return out;
}

bool _isHeading(XmlElement p) {
  for (final descendant in p.descendantElements) {
    if (descendant.name.local == 'pStyle') {
      final style = descendant.getAttribute('val') ??
          descendant.getAttribute('w:val') ??
          '';
      if (style.startsWith('Heading')) return true;
    }
  }
  return false;
}

String _paragraphText(XmlElement p) {
  final buf = StringBuffer();
  void walk(XmlElement el) {
    switch (el.name.local) {
      case 't':
        buf.write(el.innerText);
      case 'br':
        buf.write(' ');
      case 'tab':
        buf.write(' ');
    }
    for (final child in el.childElements) {
      walk(child);
    }
  }

  walk(p);
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
