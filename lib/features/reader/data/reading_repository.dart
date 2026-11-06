import 'package:drift/drift.dart';

import '../../../core/storage/database.dart';
import '../domain/viewer_prefs.dart';

/// Per-document reading position + viewer prefs (upsert semantics).
class ReadingRepository {
  ReadingRepository(this._db);

  final AppDatabase _db;

  Future<ReadingPosition?> forDoc(int docId) =>
      (_db.select(_db.readingPositions)
            ..where((r) => r.documentId.equals(docId)))
          .getSingleOrNull();

  /// Creates the row on first open so later writes can be plain updates.
  Future<ReadingPosition> ensure(int docId, {int initialPage = 1}) async {
    final existing = await forDoc(docId);
    if (existing != null) return existing;
    await _db.into(_db.readingPositions).insert(
          ReadingPositionsCompanion.insert(
            documentId: docId,
            pageNumber: initialPage,
            fitMode: ViewerFitMode.fitWidth,
            colorMode: ViewerColorMode.normal,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return (await forDoc(docId))!;
  }

  Future<void> savePage(int docId, int pageNumber) =>
      upsert(_readingPositionsCompanion(docId, pageNumber: pageNumber));

  Future<void> savePrefs(
    int docId, {
    ViewerFitMode? fitMode,
    ViewerColorMode? colorMode,
  }) =>
      upsert(_readingPositionsCompanion(
        docId,
        fitMode: fitMode,
        colorMode: colorMode,
      ));

  ReadingPositionsCompanion _readingPositionsCompanion(
    int docId, {
    int? pageNumber,
    ViewerFitMode? fitMode,
    ViewerColorMode? colorMode,
  }) =>
      ReadingPositionsCompanion(
        documentId: Value(docId),
        pageNumber:
            pageNumber == null ? const Value.absent() : Value(pageNumber),
        fitMode:
            fitMode == null ? const Value.absent() : Value(fitMode),
        colorMode:
            colorMode == null ? const Value.absent() : Value(colorMode),
        updatedAt: Value(DateTime.now()),
      );

  /// Table has no PK; upsert is read-then-write keyed by the unique documentId.
  Future<void> upsert(ReadingPositionsCompanion entry) async {
    final docId = entry.documentId.value;
    final existing = await forDoc(docId);
    if (existing == null) {
      await _db.into(_db.readingPositions).insert(
            ReadingPositionsCompanion.insert(
              documentId: docId,
              pageNumber: entry.pageNumber.present ? entry.pageNumber.value : 1,
              fitMode: entry.fitMode.present ? entry.fitMode.value : ViewerFitMode.fitWidth,
              colorMode: entry.colorMode.present
                  ? entry.colorMode.value
                  : ViewerColorMode.normal,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return;
    }
    await (_db.update(_db.readingPositions)
          ..where((r) => r.documentId.equals(docId)))
        .write(entry);
  }
}
