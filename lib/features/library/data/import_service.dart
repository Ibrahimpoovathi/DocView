import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/format/doc_format.dart';
import '../../../core/paths/app_paths.dart';
import '../../../core/storage/database.dart';
import 'library_repository.dart';
import 'metadata_service.dart';

const _supportedExtensions = {
  'pdf', 'epub', 'docx', 'docm', 'xlsx', 'xlsm', 'pptx', 'pptm',
  'txt', 'text', 'md', 'cbz', 'mobi', 'prc', 'azw3', 'kfx', 'fb2',
  'rtf', 'doc', 'odt',
};

class ImportSummary {
  final int added;
  final int duplicates;
  final int failed;
  const ImportSummary({required this.added, required this.duplicates, required this.failed});

  @override
  String toString() =>
      '$added imported, $duplicates duplicate(s) skipped, $failed failed';
}

/// Copies picked files into the sandbox, dedupes, registers rows, then
/// enriches them (title/author/covers) off the hot path.
class ImportService {
  ImportService(this._repo, this._meta);

  final LibraryRepository _repo;
  final MetadataService _meta;

  Future<ImportSummary> importSources(List<String> sourcePaths) async {
    var added = 0, duplicates = 0, failed = 0;

    for (final path in sourcePaths) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          failed++;
          continue;
        }
        final name = p.basename(path);
        final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
        if (!_supportedExtensions.contains(ext)) {
          failed++;
          continue;
        }

        final hash =
            sha256.convert(await file.readAsBytes()).toString();
        final existing = await _repo.findBySha256(hash);
        if (existing != null) {
          duplicates++;
          continue;
        }

        final uuid =
            hash.substring(0, 16) + DateTime.now().millisecondsSinceEpoch.toRadixString(36);
        final storedPath = AppPaths.bookFilePath(uuid, name);
        await Directory(p.dirname(storedPath)).create(recursive: true);
        await file.copy(storedPath);

        final size = await file.length();
        final format = DocFormat.detect(name);

        final id = await _repo.insertDocument(DocumentsCompanion.insert(
          uuid: uuid,
          format: format,
          originalName: name,
          title: p.basenameWithoutExtension(name),
          storedPath: storedPath,
          sizeBytes: size,
          sha256: hash,
        ));

        added++;
        unawaited(_enrich(id, format, storedPath));
      } on FileSystemException {
        failed++;
      }
    }
    return ImportSummary(added: added, duplicates: duplicates, failed: failed);
  }

  /// Background: resolve real metadata + cover, patch the row.
  Future<void> _enrich(int id, DocFormat format, String storedPath) async {
    final meta = await _meta.extract(format, storedPath).timeout(
          const Duration(seconds: 25),
          onTimeout: () => const DocMeta(),
        );
    String? coverPath;
    if (meta.coverPngJpg != null) {
      final doc = await _repo.byId(id);
      if (doc == null) return;
      coverPath = AppPaths.coverFilePath(doc.uuid);
      await File(coverPath).writeAsBytes(meta.coverPngJpg!);
    }
    await _repo.updateFields(
      id,
      title: meta.title,
      author: meta.author,
      pageCount: meta.pageCount,
      coverPath: coverPath,
    );
  }
}

/// Convenience for tests/UI: whole-file import from raw bytes.
extension ImportServiceBytes on ImportService {
  Future<ImportSummary> importBytes(Map<String, Uint8List> files) async {
    final dir = await Directory.systemTemp.createTemp('docview-import');
    final paths = <String>[];
    files.forEach((name, bytes) {
      final f = File(p.join(dir.path, name));
      f.writeAsBytesSync(bytes);
      paths.add(f.path);
    });
    final summary = await importSources(paths);
    await dir.delete(recursive: true);
    return summary;
  }
}
