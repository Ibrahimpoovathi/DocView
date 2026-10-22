import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/paths/app_paths.dart';
import '../../../core/storage/database.dart';
import '../domain/library_query.dart';

class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  // --- Reads ----------------------------------------------------------------

  /// Live library list honoring query (soft-deleted excluded).
  Stream<List<Document>> watchLibrary(LibraryQuery q) {
    final plainQuery = q.search.trim().toUpperCase();
    final t = _db.documents;

    Expression<bool> notDeleted() => t.deletedAt.isNull();
    final whereExpr = switch (q.chip) {
      LibraryChip.all => notDeleted(),
      LibraryChip.favourites =>
        notDeleted() & t.isFavourite.equals(true),
      LibraryChip.recent =>
        notDeleted() & t.lastOpenedAt.isNotNull(),
    };

    final query = _db.select(t)
      ..where((d) => whereExpr)
      ..orderBy(_orderFor(q.sort, t));

    if (plainQuery.isEmpty) {
      return query.watch();
    }

    // In-memory filter for P1 (FTS5 arrives in P5).
    return query.watch().map((rows) => rows
        .where((d) =>
            d.title.toUpperCase().contains(plainQuery) ||
            (d.author ?? '').toUpperCase().contains(plainQuery) ||
            d.originalName.toUpperCase().contains(plainQuery))
        .toList());
  }

  /// Continue-reading shelf: last opened, most recent first.
  Stream<List<Document>> watchContinueReading({int limit = 12}) {
    final t = _db.documents;
    return (_db.select(t)
          ..where((d) => t.deletedAt.isNull() & t.lastOpenedAt.isNotNull())
          ..orderBy([
            (d) => OrderingTerm(
                  expression: t.lastOpenedAt,
                  mode: OrderingMode.desc,
                )
          ])
          ..limit(limit))
        .watch();
  }

  List<OrderingTerm Function($DocumentsTable)> _orderFor(
    LibrarySort sort,
    $DocumentsTable t,
  ) =>
      [
        (d) => switch (sort) {
              LibrarySort.lastOpened => OrderingTerm(
                  expression: t.lastOpenedAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
              LibrarySort.addedAt => OrderingTerm(
                  expression: t.addedAt,
                  mode: OrderingMode.desc,
                ),
              LibrarySort.title => OrderingTerm(
                  expression: t.title,
                  mode: OrderingMode.asc,
                ),
              LibrarySort.sizeBytes => OrderingTerm(
                  expression: t.sizeBytes,
                  mode: OrderingMode.desc,
                ),
              LibrarySort.format => OrderingTerm(
                  expression: t.format,
                  mode: OrderingMode.asc,
                ),
            }
      ];

  Future<Document?> byId(int id) async =>
      (_db.select(_db.documents)..where((d) => d.id.equals(id) & d.deletedAt.isNull()))
          .getSingleOrNull();

  // --- Writes ---------------------------------------------------------------

  Future<Document?> findBySha256(String sha256) =>
      (_db.select(_db.documents)
            ..where((d) => d.sha256.equals(sha256) & d.deletedAt.isNull()))
          .getSingleOrNull();

  Future<int> insertDocument(DocumentsCompanion entry) =>
      _db.into(_db.documents).insert(entry);

  Future<void> updateFields(
    int id, {
    String? title,
    String? author,
    String? coverPath,
    int? pageCount,
  }) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
        DocumentsCompanion(
          title: title == null ? const Value.absent() : Value(title),
          author: author == null ? const Value.absent() : Value(author),
          coverPath: coverPath == null
              ? const Value.absent()
              : Value(coverPath),
          pageCount:
              pageCount == null ? const Value.absent() : Value(pageCount),
        ),
      );

  Future<void> markOpened(int id) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id)))
          .write(DocumentsCompanion(lastOpenedAt: Value(DateTime.now())));

  Future<void> toggleFavourite(int id, bool value) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id)))
          .write(DocumentsCompanion(isFavourite: Value(value)));

  /// Soft-deletes the row and removes its sandbox files. Returns the
  /// export-safe display data first (caller snapshots for undo UI later).
  Future<void> deleteDocument(int id) async {
    final doc = await byId(id);
    if (doc == null) return;
    await (_db.update(_db.documents)..where((d) => d.id.equals(id)))
        .write(DocumentsCompanion(deletedAt: Value(DateTime.now())));

    try {
      await AppPaths.deleteBookDir(doc.uuid);
      await AppPaths.deleteCover(doc.uuid);
    } on FileSystemException {
      // Disk layer best-effort; row is soft-deleted either way.
    }
  }

  /// Physical export: copy the stored file to [targetPath] (already picked
  /// via the OS save dialog by the UI layer).
  Future<File> exportTo(int id, String targetPath) async {
    final doc = await byId(id) ?? (throw StateError('Document $id missing'));
    return File(doc.storedPath).copy(targetPath);
  }

  // --- Collections ----------------------------------------------------------

  Stream<List<Collection>> watchCollections() =>
      (_db.select(_db.collections)..orderBy([(c) => OrderingTerm(expression: c.name)]))
          .watch();

  Future<int> createCollection(String name) =>
      _db.into(_db.collections)
          .insert(CollectionsCompanion(name: Value(name.trim())));

  Future<void> renameCollection(int id, String name) =>
      (_db.update(_db.collections)..where((c) => c.id.equals(id)))
          .write(CollectionsCompanion(name: Value(name.trim())));

  Future<void> deleteCollection(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.documentCollections)
            ..where((dc) => dc.collectionId.equals(id)))
          .go();
      await (_db.delete(_db.collections)..where((c) => c.id.equals(id))).go();
    });
  }

  /// Replaces the set of collections a document belongs to.
  Future<void> setDocumentCollections(int docId, Set<int> collectionIds) =>
      _db.transaction(() async {
        await (_db.delete(_db.documentCollections)
              ..where((dc) => dc.documentId.equals(docId)))
            .go();
        for (final cid in collectionIds) {
          await _db
              .into(_db.documentCollections)
              .insert(DocumentCollectionsCompanion.insert(
                documentId: docId,
                collectionId: cid,
              ));
        }
      });

  Future<Set<int>> collectionIdsFor(int docId) async {
    final rows = await (_db.select(_db.documentCollections)
          ..where((dc) => dc.documentId.equals(docId)))
        .get();
    return rows.map((r) => r.collectionId).toSet();
  }

  /// Documents inside a collection (for future shelf views / P6 sync).
  Stream<List<Document>> watchCollectionDocs(int collectionId) {
    final join = _db.select(_db.documents).join([
      innerJoin(_db.documentCollections, _db.documentCollections.documentId
          .equalsExp(_db.documents.id)),
    ])
      ..where(_db.documentCollections.collectionId.equals(collectionId) &
          _db.documents.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(_db.documents.lastOpenedAt)]);
    return join
        .watch()
        .map((rows) => rows.map((r) => r.readTable(_db.documents)).toList());
  }

  // --- Tags -----------------------------------------------------------------

  Stream<List<Tag>> watchTags() =>
      (_db.select(_db.tags)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch();

  Future<int> createTag(String name) =>
      _db.into(_db.tags).insert(TagsCompanion(name: Value(name.trim())));

  Future<void> setDocumentTags(int docId, Set<int> tagIds) =>
      _db.transaction(() async {
        await (_db.delete(_db.documentTags)
              ..where((dt) => dt.documentId.equals(docId)))
            .go();
        for (final tid in tagIds) {
          await _db
              .into(_db.documentTags)
              .insert(DocumentTagsCompanion.insert(
                documentId: docId,
                tagId: tid,
              ));
        }
      });

  Future<Set<int>> tagIdsFor(int docId) async {
    final rows = await (_db.select(_db.documentTags)
          ..where((dt) => dt.documentId.equals(docId)))
        .get();
    return rows.map((r) => r.tagId).toSet();
  }

  // --- Housekeeping ---------------------------------------------------------

  Future<String?> storedFileName(int id) async {
    final doc = await byId(id);
    if (doc == null) return null;
    return p.basename(doc.storedPath);
  }
}
