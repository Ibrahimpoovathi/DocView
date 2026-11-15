import 'dart:io';
import 'dart:isolate';

import 'package:docx_creator/docx_creator.dart';
import 'package:path/path.dart' as p;

import '../../../core/paths/app_paths.dart';
import '../../../core/storage/database.dart';

/// Converts DOCX to a PDF with real page geometry (A4/Letter/margins/page
/// breaks) so the reader shows documents the way Word does, instead of
/// full-width flowing text.
///
/// The conversion is CPU-bound pure Dart, runs in an isolate, and the result
/// is cached next to the source file. Oversized documents throw so the caller
/// can fall back to the lightweight DOCX viewer.
class DocxPdfCache {
  static const maxSourceBytes = 20 * 1024 * 1024;
  static const _timeout = Duration(seconds: 90);

  static Future<String> ensure(Document doc) async {
    final target = AppPaths.docxPdfPath(doc.uuid);
    final out = File(target);
    if (await out.exists()) return target;

    final source = File(doc.storedPath);
    if (!await source.exists()) {
      throw const FileSystemException('The document file is missing');
    }
    if (await source.length() > maxSourceBytes) {
      throw StateError('too large');
    }

    final bytes = await Isolate.run(
      () => PdfExporter.convertDocxFileToPdfBytes(doc.storedPath),
    ).timeout(_timeout);

    await Directory(p.dirname(target)).create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
    return target;
  }
}
