import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Paragraph of an OpenDocument Text (`.odt`) file.
class OdtParagraph {
  const OdtParagraph({required this.text, required this.isHeading});

  final String text;
  final bool isHeading;
}

/// Extract paragraphs from an `.odt` byte payload.
///
/// ODT is an Open XML-ish zip whose body lives in `content.xml` inside the
/// `urn:oasis...text` namespace as `text:p` paragraphs and `text:h` headings.
/// We walk document order so nested list paragraphs stay in reading order.
List<OdtParagraph> extractOdtParagraphs(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final content = archive.findFile('content.xml');
  if (content == null) {
    throw const FormatException('missing content.xml');
  }
  final doc = XmlDocument.parse(utf8.decode(content.content as List<int>));

  final out = <OdtParagraph>[];
  void visit(XmlElement el) {
    final name = el.name.local;
    if (name == 'p' || name == 'h') {
      final text = el.innerText.replaceAll('\n', ' ').trim();
      if (text.isNotEmpty) {
        out.add(OdtParagraph(text: text, isHeading: name == 'h'));
      }
      // Do not recurse into a paragraph (annotations could nest).
      return;
    }
    for (final child in el.childElements) {
      visit(child);
    }
  }

  // text:p/text:h appear only inside office:body, so a whole-tree walk in
  // document order is safe (styles carry no paragraph content).
  visit(doc.rootElement);
  return out;
}
