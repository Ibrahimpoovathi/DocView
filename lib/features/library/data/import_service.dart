import 'dart:async';
import 'dart:io';
import 'dart:isolate';
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

  Future<ImportSummary> importSources(
    List<String> sourcePaths, {
    void Function(int done, int total)? onProgress,
  }) async {
    var added = 0, duplicates = 0, failed = 0;

    // Hashing + file copies are I/O bound; four at a time keeps the disk busy
    // without starving the UI isolate or opening too many file handles.
    const batchSize = 4;
    final total = sourcePaths.length;
    for (var i = 0; i < total; i += batchSize) {
      final end = (i + batchSize).clamp(0, total);
      final claimed = <String>{};
      final results = await Future.wait(
        sourcePaths.sublist(i, end).map((p) => _importSingle(p, claimed: claimed)),
      );
      for (final result in results) {
        switch (result.status) {
          case _ImportStatus.added:
            added++;
          case _ImportStatus.duplicate:
            duplicates++;
          case _ImportStatus.failed:
            failed++;
        }
      }
      onProgress?.call(end, total);
    }
    return ImportSummary(added: added, duplicates: duplicates, failed: failed);
  }

  /// Imports a single file and returns the resulting document (the new row or
  /// an existing duplicate), so callers like "open with" can open it at once.
  Future<Document?> importDocument(String path) async =>
      (await _importSingle(path)).doc;

  /// [claimed] dedupes identical files picked in the same batch: without it
  /// both workers pass the pre-insert lookup and one hits UNIQUE(sha256).
  Future<_ImportResult> _importSingle(String path, {Set<String>? claimed}) async {
    try {
      final file = File(path);
      if (!await file.exists()) return const _ImportResult.failed();
      final name = p.basename(path);
      final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
      if (!_supportedExtensions.contains(ext)) {
        return const _ImportResult.failed();
      }

      // Hashing a 300MB file on the UI isolate froze the library for
      // seconds; the digest is pure compute, so run it off-thread.
      final hash = await Isolate.run(
          () => sha256.convert(File(path).readAsBytesSync()).toString());
      if (claimed != null && !claimed.add(hash)) {
        // Another file in this batch owns the hash; its row appears shortly.
        return const _ImportResult.duplicate(null);
      }
      final existing = await _repo.findBySha256(hash);
      if (existing != null) return _ImportResult.duplicate(existing);

      final size = await file.length();
      final format = DocFormat.detect(name);

      // Deleted-but-not-erased row (soft delete): restore it in place rather
      // than inserting a duplicate that violates UNIQUE(sha256).
      final deleted = await _repo.findBySha256(hash, includeDeleted: true);
      if (deleted != null) {
        final storedPath = AppPaths.bookFilePath(deleted.uuid, name);
        await Directory(p.dirname(storedPath)).create(recursive: true);
        await file.copy(storedPath);
        await _repo.reviveDocument(
          deleted.id,
          originalName: name,
          storedPath: storedPath,
          sizeBytes: size,
          format: format,
        );
        unawaited(_enrich(deleted.id, format, storedPath));
        return _ImportResult.added(await _repo.byId(deleted.id));
      }

      final uuid = hash.substring(0, 16) +
          DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final storedPath = AppPaths.bookFilePath(uuid, name);
      await Directory(p.dirname(storedPath)).create(recursive: true);
      await file.copy(storedPath);

      final int id;
      try {
        id = await _repo.insertDocument(DocumentsCompanion.insert(
          uuid: uuid,
          format: format,
          originalName: name,
          title: p.basenameWithoutExtension(name),
          storedPath: storedPath,
          sizeBytes: size,
          sha256: hash,
        ));
      } on Object {
        // Belt and braces for a same-hash race we could not see in [claimed]
        // (e.g. a concurrent import from the share sheet).
        final row = await _repo.findBySha256(hash);
        if (row != null) return _ImportResult.duplicate(row);
        rethrow;
      }

      unawaited(_enrich(id, format, storedPath));
      return _ImportResult.added(await _repo.byId(id));
    } on FileSystemException {
      return const _ImportResult.failed();
    }
  }

  /// Background: resolve real metadata + cover, patch the row.
  /// Best-effort — a failing extractor must never crash the zone (this runs
  /// unawaited off the import path).
  Future<void> _enrich(int id, DocFormat format, String storedPath) async {
    try {
      // EPUB unzip + XML parsing is CPU-bound; keep it off the UI isolate.
      final extraction = format == DocFormat.epub
          ? Isolate.run(() => MetadataService().extract(format, storedPath))
          : _meta.extract(format, storedPath);
      final meta = await extraction.timeout(
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
    } on Object {
      // Enrichment is cosmetic; the import row stays as inserted.
    }
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

enum _ImportStatus { added, duplicate, failed }

class _ImportResult {
  const _ImportResult.added(this.doc) : status = _ImportStatus.added;
  const _ImportResult.duplicate(this.doc) : status = _ImportStatus.duplicate;
  const _ImportResult.failed()
      : status = _ImportStatus.failed,
        doc = null;

  final _ImportStatus status;
  final Document? doc;
}
