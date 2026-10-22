import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:xml/xml.dart';

import '../../../core/format/doc_format.dart';

/// Resolved metadata + optional generated cover.
class DocMeta {
  const DocMeta({this.title, this.author, this.pageCount, this.coverPngJpg});
  final String? title;
  final String? author;
  final int? pageCount;

  /// Encoded JPEG bytes of the generated cover, ready to write to disk.
  final Uint8List? coverPngJpg;
}

/// Extracts title/author/page-count and generates covers off the UI thread.
class MetadataService {
  Future<DocMeta> extract(DocFormat format, String storedPath) =>
      switch (format) {
        DocFormat.pdf => _pdf(storedPath),
        DocFormat.epub => _epub(storedPath),
        _ => Future.value(const DocMeta()),
      };

  // --- PDF (pdfrx / pdfium) -------------------------------------------------

  Future<DocMeta> _pdf(String path) async {
    pdfrx.PdfDocument? doc;
    try {
      doc = await pdfrx.PdfDocument.openFile(path);
      final pageCount = doc.pages.length;
      String? title;
      Uint8List? cover;
      final page = pageCount > 0 ? doc.pages.first : null;
      if (page != null) {
        final image = await page.render(
          fullWidth: page.width * 2,
          fullHeight: page.height * 2,
        );
        if (image != null) {
          final prepped =
              image.createImageNF(pixelSizeThreshold: 480);
          image.dispose();
          cover = Uint8List.fromList(encodeJpg(prepped, quality: 84));
        }
      }
      // pdfrx engine does not expose Info dict headers in 0.4.x; fall back to
      // filename at insert time.
      return DocMeta(pageCount: pageCount, coverPngJpg: cover, title: title);
    } catch (_) {
      return const DocMeta(); // corrupt/encrypted PDFs still show in library
    } finally {
      try {
        await doc?.dispose();
      } catch (_) {}
    }
  }

  // --- EPUB (minimal container → OPF walk; no full parse) -------------------

  Future<DocMeta> _epub(String path) async {
    Archive? zip;
    try {
      final bytes = File(path).readAsBytesSync();
      zip = ZipDecoder().decodeBytes(bytes, verify: false);

      String? opfPath;
      final container = zip.findFile('META-INF/container.xml');
      if (container != null) {
        final xmlText = String.fromCharCodes(container.content);
        opfPath = _firstRootfile(xmlText);
      }

      final title = <String>[];
      String? author;
      Uint8List? cover;

      if (opfPath != null) {
        final opf = zip.findFile(opfPath);
        if (opf != null) {
          final doc = XmlDocument.parse(String.fromCharCodes(opf.content));
          title.addAll(_opfTitle(doc));
          author = _opfAuthor(doc);
          final coverHref = _opfCoverHref(doc);
          if (coverHref != null) {
            final opfDir = p.posix.dirname(opfPath);
            final imgPath =
                opfDir == '.' ? coverHref : p.posix.join(opfDir, coverHref);
            final imgFile = zip.findFile(imgPath) ?? zip.findFile(coverHref);
            if (imgFile != null) {
              cover = _encodeCoverJpg(imgFile.content, maxDim: 480);
            }
          }
        }
      }
      return DocMeta(
        title: title.isEmpty ? null : title.first,
        author: author,
        coverPngJpg: cover,
      );
    } catch (_) {
      return const DocMeta();
    } finally {
      // Archive objects are plain memory handles; nothing to close.
    }
  }

  /// Shared EPUB/CBZ helper: decode an embedded image and re-encode as JPEG
  /// sized for the library card.
  static Uint8List? _encodeCoverJpg(List<int> bytes, {int maxDim = 480}) {
    try {
      final decoded = decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return null;
      var img = decoded;
      if (img.width > maxDim || img.height > maxDim) {
        img = copyResize(
          img,
          width: img.width >= img.height ? maxDim : null,
          height: img.height > img.width ? maxDim : null,
          interpolation: Interpolation.linear,
        );
      }
      return Uint8List.fromList(encodeJpg(img, quality: 84));
    } catch (_) {
      return null;
    }
  }

  static String? _firstRootfile(String containerXml) {
    try {
      final doc = XmlDocument.parse(containerXml);
      final path = doc.findAllElements('rootfile').firstOrNull
          ?.getAttribute('full-path');
      return (path == null || path.isEmpty) ? null : path;
    } catch (_) {
      return null;
    }
  }

  static Iterable<String> _opfTitle(XmlDocument opf) => opf
      .findAllElements('title', namespace: '*')
      .map((e) => e.innerText.trim())
      .where((t) => t.isNotEmpty);

  static String? _opfAuthor(XmlDocument opf) {
    for (final e in opf.findAllElements('creator', namespace: '*')) {
      final name = e.innerText.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  /// Manifest item with properties containing "cover-image" (EPUB 3) or the
  /// legacy meta[name=cover content=<id>] (EPUB 2).
  static String? _opfCoverHref(XmlDocument opf) {
    final manifest = {for (final i in opf.findAllElements('item', namespace: '*'))
      i.getAttribute('id'): i};
    // EPUB 3: properties="cover-image ..."
    for (final item in opf.findAllElements('item', namespace: '*')) {
      final props = item.getAttribute('properties') ?? '';
      if (props.split(' ').contains('cover-image')) {
        final href = item.getAttribute('href');
        if (href != null) return href;
      }
    }
    // EPUB 2: <meta name="cover" content="cover-id"/>
    for (final m in opf.findAllElements('meta', namespace: '*')) {
      if ((m.getAttribute('name') ?? '') == 'cover') {
        final id = m.getAttribute('content');
        final href = id == null ? null : manifest[id]?.getAttribute('href');
        if (href != null) return href;
      }
    }
    return null;
  }
}
