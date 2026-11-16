import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/format/doc_format.dart';
import '../../../core/paths/app_paths.dart';
import '../../../core/storage/database.dart';
import '../domain/library_query.dart';

class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  /// Builds a safe FTS5 MATCH string out of free-text user input.
  /// Returns null when there is nothing matchable (empty/whitespace/punctuation).
  static String? ftsMatchQuery(String raw) {
    final words = RegExp(r'[\p{L}\p{N}_]+', unicode: true)
        .allMatches(raw)
        .map((m) => m.group(0)!)
        .take(8)
        .toList();
    if (words.isEmpty) return null;
    return words.map((w) => '"$w"').join(' ');
  }

  // --- Reads ----------------------------------------------------------------

  /// Live library list honoring query (soft-deleted excluded).
  ///
  /// When a search term is present we go through FTS5 (title, author, body)
  /// ranked by bm25; otherwise the plain drift query keeps the chosen sort.
  Stream<List<Document>> watchLibrary(LibraryQuery q) {
    final term = ftsMatchQuery(q.search);
    if (term == null) {
      final t = _db.documents;
      final plainQuery = q.search.trim().toUpperCase();

      Expression<bool> notDeleted() => t.deletedAt.isNull();
      final collectionId = q.collectionId;
      final inCollection = collectionId == null
          ? const Constant(true)
          : existsQuery(_db.select(_db.documentCollections)
            ..where((dc) =>
                dc.collectionId.equals(collectionId) &
                dc.documentId.equalsExp(t.id)));
      final whereExpr = switch (q.chip) {
            LibraryChip.all => notDeleted(),
            LibraryChip.favourites =>
              notDeleted() & t.isFavourite.equals(true),
            LibraryChip.recent =>
              notDeleted() & t.lastOpenedAt.isNotNull(),
          } &
          inCollection;

      final query = _db.select(t)
        ..where((d) => whereExpr)
        ..orderBy(_orderFor(q.sort, t));

      if (plainQuery.isEmpty) {
        return query.watch();
      }

      // Fallback while the FTS index still fills in: substring match on
      // metadata only (fast, no rank ordering).
      return query.watch().map((rows) => rows
          .where((d) =>
              d.title.toUpperCase().contains(plainQuery) ||
              (d.author ?? '').toUpperCase().contains(plainQuery) ||
              d.originalName.toUpperCase().contains(plainQuery))
          .toList());
    }

    // FTS5 path. Chip filters + no in-memory post-filter (FTS covers it).
    final chipSql = switch (q.chip) {
      LibraryChip.all => '',
      LibraryChip.favourites => ' AND d.is_favourite = 1',
      LibraryChip.recent => ' AND d.last_opened_at IS NOT NULL',
    };
    final collectionId = q.collectionId;
    final collectionSql = collectionId == null
        ? ''
        : ' AND EXISTS (SELECT 1 FROM document_collections dc '
            'WHERE dc.document_id = d.id '
            'AND dc.collection_id = $collectionId)';
    return _db
        .customSelect(
          'SELECT d.* FROM documents d '
          'JOIN document_fts f ON f.rowid = d.id '
          "WHERE d.deleted_at IS NULL$chipSql$collectionSql "
          'AND document_fts MATCH ? '
          'ORDER BY bm25(document_fts)',
          variables: [Variable.withString(term)],
          readsFrom: {_db.documents, _db.documentCollections},
        )
        .watch()
        // mapFromRow is Future-based; map() on the table info is the sync
        // equivalent and handles enum/datetime/bool conversions itself.
        .map((rows) => [
              for (final row in rows) _db.documents.map(row.data),
            ]);
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

  /// Includes soft-deleted rows (undo purge needs their file paths).
  Future<Document?> byIdAny(int id) =>
      (_db.select(_db.documents)..where((d) => d.id.equals(id)))
          .getSingleOrNull();

  // --- Writes ---------------------------------------------------------------

  Future<Document?> findBySha256(String sha256, {bool includeDeleted = false}) =>
      (_db.select(_db.documents)
            ..where((d) => includeDeleted
                ? d.sha256.equals(sha256)
                : d.sha256.equals(sha256) & d.deletedAt.isNull()))
          .getSingleOrNull();

  /// Restores a soft-deleted row so a re-imported file reuses it instead of
  /// colliding with the UNIQUE(sha256) index.
  Future<void> reviveDocument(
    int id, {
    required String originalName,
    required String storedPath,
    required int sizeBytes,
    required DocFormat format,
  }) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(id)))
        .write(DocumentsCompanion(
      originalName: Value(originalName),
      storedPath: Value(storedPath),
      sizeBytes: Value(sizeBytes),
      format: Value(format),
      deletedAt: const Value(null),
      updatedAt: Value(DateTime.now()),
      // Deletion dropped the FTS body; mark it for re-extraction.
      textIndexed: const Value(0),
    ));
    final row = await (_db.select(_db.documents)
          ..where((d) => d.id.equals(id)))
        .getSingleOrNull();
    if (row != null) {
      // Recreate the metadata entry (body comes back via the indexer).
      await _syncFtsMeta(row.id, row.title, row.author);
    }
  }

  Future<int> insertDocument(DocumentsCompanion entry) async {
    final stamped = entry.updatedAt.present
        ? entry
        : entry.copyWith(updatedAt: Value(DateTime.now()));
    final id = await _db.into(_db.documents).insert(stamped);
    final row = await (_db.select(_db.documents)
          ..where((d) => d.id.equals(id)))
        .getSingleOrNull();
    if (row != null) {
      await _syncFtsMeta(row.id, row.title, row.author);
    }
    return id;
  }

  Future<void> updateFields(
    int id, {
    String? title,
    String? author,
    String? coverPath,
    int? pageCount,
  }) async {
    if (title != null || author != null) {
      final doc = await byId(id);
      final newTitle = title ?? doc?.title;
      final newAuthor = author ?? doc?.author;
      if (newTitle != null) {
        await _syncFtsMeta(id, newTitle, newAuthor);
      }
    }
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(
        title: title == null ? const Value.absent() : Value(title),
        author: author == null ? const Value.absent() : Value(author),
        coverPath: coverPath == null
            ? const Value.absent()
            : Value(coverPath),
        pageCount:
            pageCount == null ? const Value.absent() : Value(pageCount),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Keeps the FTS5 row in step with document metadata without clobbering
  /// any previously indexed body text. (FTS5 virtual tables don't support
  /// UPSERT — read the old body, then DELETE + INSERT in one transaction.)
  Future<void> _syncFtsMeta(int id, String title, String? author) async {
    final existing = await _db
        .customSelect('SELECT body FROM document_fts WHERE rowid = ?',
            variables: [Variable.withInt(id)])
        .getSingleOrNull();
    final body = existing == null ? '' : (existing.data['body'] ?? '') as String;
    await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM document_fts WHERE rowid = ?',
        [id],
      );
      await _db.customStatement(
        'INSERT INTO document_fts(rowid, title, author, body) '
        'VALUES(?, ?, ?, ?)',
        [id, title, author ?? '', body],
      );
    });
  }

  Future<void> markOpened(int id) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id)))
          .write(DocumentsCompanion(
              lastOpenedAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now())));

  Future<void> toggleFavourite(int id, bool value) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id)))
          .write(DocumentsCompanion(
              isFavourite: Value(value), updatedAt: Value(DateTime.now())));

  /// Tombstones the row and drops it from search.
  ///
  /// With [keepArtifacts] the reading position, group links, annotation
  /// tombstones and sandbox files are retained so the UI can offer an undo;
  /// [`purgeDocumentArtifacts`] must then run once the undo window closes.
  Future<void> deleteDocument(int id, {bool keepArtifacts = false}) async {
    final doc = await byId(id);
    if (doc == null) return;
    await (_db.update(_db.documents)..where((d) => d.id.equals(id)))
        .write(DocumentsCompanion(
            deletedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now())));

    // Drop the FTS row so deleted bodies never surface in searches.
    await _db.customStatement(
      'DELETE FROM document_fts WHERE rowid = ?',
      [id],
    );

    if (!keepArtifacts) await purgeDocumentArtifacts(id);
  }

  /// Removes everything still attached to a soft-deleted row: positions,
  /// group links, annotation tombstones and sandbox files. Idempotent, so it
  /// is safe as the undo window's fallback and as a boot sweep.
  Future<void> purgeDocumentArtifacts(int id) async {
    final doc = await byIdAny(id);
    if (doc == null || doc.deletedAt == null) return;

    // Cascade: positions and group links would otherwise linger forever and
    // resurface if the same file is re-imported.
    await (_db.delete(_db.readingPositions)
          ..where((r) => r.documentId.equals(id)))
        .go();
    await (_db.delete(_db.documentCollections)
          ..where((dc) => dc.documentId.equals(id)))
        .go();
    await (_db.delete(_db.documentTags)
          ..where((dt) => dt.documentId.equals(id)))
        .go();
    // Annotations are tombstoned (not deleted) so removals propagate via sync.
    await (_db.update(_db.annotations)
          ..where((a) => a.documentId.equals(id) & a.deletedAt.isNull()))
        .write(AnnotationsCompanion(
      deletedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));

    try {
      await AppPaths.deleteBookDir(doc.uuid);
      await AppPaths.deleteCover(doc.uuid);
    } on FileSystemException {
      // Disk layer best-effort; row stays soft-deleted either way.
    }
  }

  /// Boot safety net: app was killed inside the undo window (or a previous
  /// purge failed), so finish cleanup for every tombstoned row.
  Future<void> purgeAbandonedArtifacts() async {
    final rows = await (_db.select(_db.documents)
          ..where((d) => d.deletedAt.isNotNull()))
        .get();
    for (final row in rows) {
      await purgeDocumentArtifacts(row.id);
    }
  }

  /// Physical export: copy the stored file to [targetPath] (already picked
  /// via the OS save dialog by the UI layer).
  Future<File> exportTo(int id, String targetPath) async {
    final doc = await byId(id) ?? (throw StateError('Document $id missing'));
    return File(doc.storedPath).copy(targetPath);
  }

  // --- Collections ----------------------------------------------------------

  Stream<List<Collection>> watchCollections() => (_db.select(_db.collections)
        ..where((c) => c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm(expression: c.name)]))
      .watch();

  Future<int> createCollection(String name) async {
    final trimmed = name.trim();
    final existing = await (_db.select(_db.collections)
          ..where((c) => c.name.equals(trimmed)))
        .getSingleOrNull();
    if (existing != null) {
      if (existing.deletedAt != null) {
        // Re-creating a deleted name revives the row (no UNIQUE violation).
        await (_db.update(_db.collections)..where((c) => c.id.equals(existing.id)))
            .write(CollectionsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ));
      }
      return existing.id;
    }
    return _db.into(_db.collections).insert(CollectionsCompanion(
          name: Value(trimmed),
          updatedAt: Value(DateTime.now()),
        ));
  }

  Future<void> renameCollection(int id, String name) =>
      (_db.update(_db.collections)..where((c) => c.id.equals(id)))
          .write(CollectionsCompanion(
        name: Value(name.trim()),
        updatedAt: Value(DateTime.now()),
      ));

  /// Soft-deletes a collection (tombstone) and drops its document links.
  Future<void> deleteCollection(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.documentCollections)
            ..where((dc) => dc.collectionId.equals(id)))
          .go();
      await (_db.update(_db.collections)..where((c) => c.id.equals(id)))
          .write(CollectionsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
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

  Stream<List<Tag>> watchTags() => (_db.select(_db.tags)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .watch();

  Future<int> createTag(String name) async {
    final trimmed = name.trim();
    final existing = await (_db.select(_db.tags)
          ..where((t) => t.name.equals(trimmed)))
        .getSingleOrNull();
    if (existing != null) {
      if (existing.deletedAt != null) {
        await (_db.update(_db.tags)..where((t) => t.id.equals(existing.id)))
            .write(TagsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ));
      }
      return existing.id;
    }
    return _db.into(_db.tags).insert(TagsCompanion(
          name: Value(trimmed),
          updatedAt: Value(DateTime.now()),
        ));
  }

  /// Soft-deletes a tag (tombstone) and drops its document links.
  Future<void> deleteTag(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.documentTags)..where((dt) => dt.tagId.equals(id)))
          .go();
      await (_db.update(_db.tags)..where((t) => t.id.equals(id)))
          .write(TagsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

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
