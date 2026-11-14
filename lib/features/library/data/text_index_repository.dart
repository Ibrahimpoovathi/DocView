import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/storage/database.dart';
import 'library_repository.dart';
import 'text_extract.dart';

/// Background FTS5 body-text indexer.
///
/// Picks documents whose `text_indexed` is still 0, extracts their body text
/// off the UI thread, and writes it into `document_fts` (or marks them done
/// with an empty body for formats we do not extract). Idempotent: safe to
/// kick repeatedly from boot / imports.
class TextIndexRepository {
  TextIndexRepository(this._db);

  final AppDatabase _db;

  static bool _running = false;

  /// Process pending documents; returns how many were handled.
  Future<int> runPending({int batch = 8}) async {
    if (_running) return 0;
    _running = true;
    var done = 0;
    try {
      final t = _db.documents;
      final rows = await (_db.select(t)
            ..where((d) =>
                d.deletedAt.isNull() & d.textIndexed.equals(0))
            // Newest first: freshly imported docs are the ones the user is
            // most likely to search next; stale backlog trails behind.
            ..orderBy([(u) => OrderingTerm(
                expression: u.id, mode: OrderingMode.desc)]))
          .get();

      for (final doc in rows.take(batch)) {
        final extractable = bodyIndexableFormats.contains(doc.format);
        final body = extractable
            ? await extractBodyText(doc.storedPath, doc.format)
            : '';

        // Mark done first (drives library re-query), then upsert the row.
        await (_db.update(_db.documents)
              ..where((d) => d.id.equals(doc.id)))
            .write(DocumentsCompanion(textIndexed: const Value(1)));
        await _upsert(doc.id, doc.title, doc.author ?? '', body);
        done++;
      }
    } on Object {
      // Best effort — indexing failures never block the app.
    } finally {
      _running = false;
    }
    return done;
  }

  /// Body search convenience shared by tests: how many docs are still pending.
  Future<int> pendingCount() async {
    final t = _db.documents;
    return await (_db.select(t)
          ..where((d) => d.deletedAt.isNull() & t.textIndexed.equals(0)))
        .get()
        .then((r) => r.length);
  }

  Future<void> _upsert(int rowid, String title, String author, String body) =>
      _db.transaction(() async {
        await _db.customStatement(
          'DELETE FROM document_fts WHERE rowid = ?',
          [rowid],
        );
        await _db.customStatement(
          'INSERT INTO document_fts(rowid, title, author, body) '
          'VALUES(?, ?, ?, ?)',
          [rowid, title, author, body],
        );
      });

  // Re-exported so repositories/tests share one definition.
  static String? ftsMatch(String raw) => LibraryRepository.ftsMatchQuery(raw);
}
