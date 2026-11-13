import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/format/doc_format.dart';
import '../../../core/paths/app_paths.dart';
import '../../../core/storage/database.dart';
import '../../reader/data/annotations_repository.dart';
import '../../reader/domain/annotations.dart';
import '../../../features/reader/domain/viewer_prefs.dart';
import 'sync_manifest.dart';
import 'webdav_sync.dart';

/// Outcome of one sync run, for UI feedback lines.
class SyncResult {
  final int uploadedBooks;
  final int uploadedCovers;
  final int newRemoteDocs;
  final int mergedMetadata;
  final int appliedTombstones;
  final int appliedUndeletes;
  final int mergedPositions;
  final int mergedAnnotations;

  const SyncResult({
    required this.uploadedBooks,
    required this.uploadedCovers,
    required this.newRemoteDocs,
    required this.mergedMetadata,
    required this.appliedTombstones,
    required this.appliedUndeletes,
    required this.mergedPositions,
    this.mergedAnnotations = 0,
  });

  String get summary {
    final parts = <String>[
      if (uploadedBooks > 0) 'Pushed $uploadedBooks book(s)',
      if (newRemoteDocs > 0) 'Pulled $newRemoteDocs doc(s)',
      if (mergedMetadata > 0) 'Updated $mergedMetadata metadata row(s)',
      if (mergedPositions > 0) 'Merged $mergedPositions position(s)',
      if (mergedAnnotations > 0) 'Merged $mergedAnnotations annotation(s)',
      if (appliedTombstones > 0) 'Removed $appliedTombstones',
      if (appliedUndeletes > 0) 'Restored $appliedUndeletes',
      if (uploadedCovers > 0) 'Covers: $uploadedCovers up',
    ];
    return parts.isEmpty ? 'Already in sync' : parts.join(' · ');
  }
}

/// Pull-reconcile-push WebDAV sync for DocView.
///
/// Identity: documents reconcile by `sha256` (content address); uuids are
/// carried in the manifest and adopted when inserting remote-only docs.
/// Metadata LWW uses `Documents.updatedAt` (null loses to non-null);
/// reading positions LWW uses `ReadingPositions.updatedAt`.
class SyncEngine {
  SyncEngine(this._db, this._dav, {this.onStep});

  final AppDatabase _db;
  final WebdavBackend _dav;
  AnnotationsRepository get _annRepo => AnnotationsRepository(_db);

  /// Coarse progress for UI ("Pulling manifest…", "Uploading 2/5 …").
  final void Function(String step)? onStep;

  Future<SyncResult> run() async {
    await _dav.ensureDirs();

    onStep?.call('Reading manifest…');
    final remoteJson = await _dav.readManifest();
    final remote = remoteJson == null ? null : SyncManifest.fromJson(remoteJson);

    final remoteBooks = await _dav.listBooks();
    final remoteCovers = await _dav.listCoverShas();

    final pulled = await _pull(remote, remoteBooks, remoteCovers);
    final pushed = await _push(remoteBooks, remoteCovers);
    return SyncResult(
      uploadedBooks: pushed.books,
      uploadedCovers: pushed.covers,
      newRemoteDocs: pulled.newDocs,
      mergedMetadata: pulled.metadata,
      appliedTombstones: pulled.tombstones,
      appliedUndeletes: pulled.undeletes,
      mergedPositions: pulled.positions,
      mergedAnnotations: pulled.annotations,
    );
  }

  // --- Local snapshot -------------------------------------------------------

  Future<Map<String, Document>> _docsBySha() async {
    final rows = await _db.select(_db.documents).get();
    return {for (final r in rows) r.sha256: r};
  }

  // --- Pull -----------------------------------------------------------------

  Future<({int newDocs, int metadata, int tombstones, int undeletes, int positions, int annotations})>
      _pull(SyncManifest? remote, Map<String, int> remoteBooks,
          Set<String> remoteCovers) async {
    var newDocs = 0, metadata = 0, tombstones = 0, undeletes = 0, positions = 0, annotations = 0;
    if (remote == null) {
      return (
        newDocs: 0, metadata: 0, tombstones: 0, undeletes: 0, positions: 0, annotations: 0
      );
    }

    final localBySha = await _docsBySha();
    final shaToId = <String, int>{
      for (final e in localBySha.entries) e.key: e.value.id,
    };

    await _db.transaction(() async {
      // 1. Documents (metadata LWW + tombstones).
      for (final rd in remote.documents) {
        final ld = localBySha[rd.sha256];
        if (ld == null) {
          final newId = await _insertRemoteDoc(rd, remoteBooks, remoteCovers);
          shaToId[rd.sha256] = newId;
          newDocs++;
          continue;
        }
        shaToId[rd.sha256] = ld.id;

        // Tombstone/undelete resolution is last-writer-wins too: the newer
        // of (remote.deletedAt | remote.updatedAt) vs
        // (local.deletedAt | local.updatedAt) decides. Without this, a
        // device would resurrect its own just-deleted doc from its own
        // earlier manifest push.
        final localMutation = ld.deletedAt ?? ld.updatedAt;
        final remoteMutation = rd.deletedAt ?? rd.updatedAt;

        if (rd.deletedAt != null && ld.deletedAt == null) {
          // Remote tombstone; a newer local mutation keeps the doc alive
          // (push will then revive it on the remote side).
          final localNewer = localMutation != null &&
              remoteMutation != null &&
              localMutation.isAfter(remoteMutation);
          if (!localNewer) {
            await _softDeleteLocal(ld);
            tombstones++;
            continue;
          }
        } else if (rd.deletedAt == null && ld.deletedAt != null) {
          // Remote alive again; undelete only on a strictly newer remote
          // mutation — equal timestamps (same second) keep the local
          // tombstone, so a device never resurrects its own delete.
          final remoteNewer = remoteMutation != null &&
              localMutation != null &&
              remoteMutation.isAfter(localMutation);
          if (remoteNewer) {
            await _undeleteLocal(ld);
            undeletes++;
            continue;
          }
        }

        // Metadata LWW: remote mutation newer than local's?
        final ru = rd.updatedAt;
        final lu = ld.updatedAt;
        if (ru != null && (lu == null || ru.isAfter(lu))) {
          await (_db.update(_db.documents)..where((d) => d.id.equals(ld.id)))
              .write(DocumentsCompanion(
            title: rd.title.isEmpty ? const Value.absent() : Value(rd.title),
            author: Value(rd.author),
            isFavourite: Value(rd.favourite),
            pageCount: Value(rd.pageCount),
            updatedAt: Value(ru),
          ));
          await _upsertFtsMeta(ld.id, rd.title, rd.author);
          metadata++;
        } else if (lu == null && ru == null) {
          // Legacy rows (pre-v5 both sides): prefer remote only when the
          // remote row was synced after the local row was added.
          final remoteAdded = rd.addedAt;
          if (remoteAdded != null && remoteAdded.isAfter(ld.addedAt)) {
            await (_db.update(_db.documents)..where((d) => d.id.equals(ld.id)))
                .write(DocumentsCompanion(
              title: rd.title.isEmpty ? const Value.absent() : Value(rd.title),
              author: Value(rd.author),
              isFavourite: Value(rd.favourite),
              pageCount: Value(rd.pageCount),
            ));
            await _upsertFtsMeta(ld.id, rd.title, rd.author);
            metadata++;
          }
        }
      }

      // 2. Reading positions (per-row LWW).
      final localPositions = <String, ReadingPosition>{};
      final posRows = await (_db.select(_db.readingPositions).join([
        innerJoin(_db.documents, _db.documents.id.equalsExp(
            _db.readingPositions.documentId)),
      ])).get();
      for (final row in posRows) {
        final doc = row.readTable(_db.documents);
        final pos = row.readTable(_db.readingPositions);
        localPositions[doc.sha256] = pos;
      }

      for (final rp in remote.positions) {
        final docId = shaToId[rp.sha256];
        if (docId == null) continue; // doc vanished on both sides
        final local = localPositions[rp.sha256];
        if (local == null) {
          await _db.into(_db.readingPositions).insert(
                ReadingPositionsCompanion.insert(
                  documentId: docId,
                  pageNumber: rp.lastPage,
                  progress: Value(rp.fraction),
                  location: Value(rp.location),
                  fitMode: _fit(rp.fitMode),
                  colorMode: _color(rp.colorMode),
                  updatedAt: Value(rp.updatedAt ?? DateTime.now()),
                ),
              );
          positions++;
        } else if (rp.newerThan(_syncPos(local))) {
          await (_db.update(_db.readingPositions)
                ..where((r) => r.documentId.equals(docId)))
              .write(ReadingPositionsCompanion(
            pageNumber: Value(rp.lastPage),
            progress: Value(rp.fraction),
            location: Value(rp.location),
            fitMode: Value(_fit(rp.fitMode)),
            colorMode: Value(_color(rp.colorMode)),
            updatedAt: Value(rp.updatedAt ?? DateTime.now()),
          ));
          positions++;
        }
      }

      // 3. Collections & tags by name; joins merged.
      await _mergeNames(remote.collections, _db.collections);
      await _mergeTags(remote.tags);
      await _mergeJoins(remote);

      // 4. Annotations by uuid (LWW + deletion-dominant ties in the repo).
      for (final ra in remote.annotations) {
        final docId = shaToId[ra.sha256];
        if (docId == null) continue; // doc unknown on both sides
        AnnotationKind? kind;
        for (final k in AnnotationKind.values) {
          if (k.name == ra.kind) kind = k;
        }
        if (kind == null) continue;
        await _annRepo.upsertRemote(AnnotationsCompanion.insert(
          uuid: ra.uuid,
          documentId: docId,
          kind: kind,
          anchor: ra.anchor,
          excerpt: Value(ra.excerpt),
          note: Value(ra.note),
          color: Value(ra.color),
          createdAt: Value(ra.createdAt ?? DateTime.now()),
          updatedAt: Value(ra.updatedAt),
          deletedAt: Value(ra.deletedAt),
        ));
        annotations++;
      }
    });

    return (
      newDocs: newDocs,
      metadata: metadata,
      tombstones: tombstones,
      undeletes: undeletes,
      positions: positions,
      annotations: annotations,
    );
  }

  Future<int> _insertRemoteDoc(SyncDoc rd, Map<String, int> remoteBooks,
      Set<String> remoteCovers) async {
    // Recover the original file name from the remote book file listing
    // (books are stored as `<sha256>__<originalName>`); fall back to a
    // synthetic name so storedPath can still be planned.
    final origName = remoteBooks.keys
        .where((n) => _shaOf(n) == rd.sha256)
        .map(_origOf)
        .firstOrNull ??
        '${rd.title}.${rd.format}';
    final uuid = rd.uuid;
    final storedPath = AppPaths.bookFilePath(uuid, origName);

    final coverPath =
        remoteCovers.contains(rd.sha256) ? AppPaths.coverFilePath(uuid) : null;

    final id = await _db.into(_db.documents).insert(DocumentsCompanion.insert(
          uuid: uuid,
          format: _format(rd.format),
          originalName: origName,
          title: rd.title,
          author: Value(rd.author),
          storedPath: storedPath,
          coverPath: Value(coverPath),
          sizeBytes: remoteBooks.entries
                  .where((e) => _shaOf(e.key) == rd.sha256)
                  .map((e) => e.value)
                  .firstOrNull ??
              0,
          sha256: rd.sha256,
          pageCount: Value(rd.pageCount),
          isFavourite: Value(rd.favourite),
          addedAt: Value(rd.addedAt ?? DateTime.now()),
          lastOpenedAt: Value(rd.lastOpenedAt),
          deletedAt: Value(rd.deletedAt),
          // Cloud-only rows are pre-marked indexed (no body until the file
          // lands); the downloader resets this to trigger extraction.
          textIndexed: const Value(1),
          updatedAt: Value(rd.updatedAt),
        ));

    // Metadata-only FTS row so remote titles are searchable before download.
    await _upsertFtsMeta(id, rd.title, rd.author);

    if (coverPath != null) {
      final bytes = await _dav.readCover(rd.sha256);
      if (bytes != null) {
        await File(coverPath).create(recursive: true);
        await File(coverPath).writeAsBytes(bytes);
      }
    }
    return id;
  }

  Future<void> _softDeleteLocal(Document ld) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(ld.id))).write(
        DocumentsCompanion(
            deletedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now())));
    await _db.customStatement(
      'DELETE FROM document_fts WHERE rowid = ?',
      [ld.id],
    );
  }

  Future<void> _undeleteLocal(Document ld) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(ld.id))).write(
        DocumentsCompanion(
            deletedAt: const Value(null), textIndexed: const Value(0)));
    await _upsertFtsMeta(ld.id, ld.title, ld.author);
  }

  Future<void> _mergeNames(List<String> names, $CollectionsTable table) async {
    final existing = await _db.select(_db.collections).get();
    final have = existing.map((c) => c.name).toSet();
    for (final name in names) {
      if (!have.contains(name)) {
        await _db.into(_db.collections).insert(
              CollectionsCompanion.insert(name: name),
            );
      }
    }
  }

  Future<void> _mergeTags(List<String> names) async {
    final existing = await _db.select(_db.tags).get();
    final have = existing.map((t) => t.name).toSet();
    for (final name in names) {
      if (!have.contains(name)) {
        await _db
            .into(_db.tags)
            .insert(TagsCompanion.insert(name: name));
      }
    }
  }

  Future<void> _mergeJoins(SyncManifest remote) async {
    final docs = await _docsBySha();
    final shaToId = {for (final e in docs.entries) e.key: e.value.id};
    final collections = await _db.select(_db.collections).get();
    final colByName = {for (final c in collections) c.name: c.id};
    final tags = await _db.select(_db.tags).get();
    final tagByName = {for (final t in tags) t.name: t.id};

    final existingColJoins = await _db.select(_db.documentCollections).get();
    final haveCol = existingColJoins
        .map((j) => '${j.documentId}:${j.collectionId}')
        .toSet();
    for (final link in remote.documentCollections) {
      final docId = shaToId[link.sha256];
      final colId = colByName[link.name];
      if (docId == null || colId == null) continue;
      final key = '$docId:$colId';
      if (!haveCol.contains(key)) {
        await _db.into(_db.documentCollections).insert(
              DocumentCollectionsCompanion.insert(
                documentId: docId,
                collectionId: colId,
              ),
            );
      }
    }

    final existingTagJoins = await _db.select(_db.documentTags).get();
    final haveTag = existingTagJoins
        .map((j) => '${j.documentId}:${j.tagId}')
        .toSet();
    for (final link in remote.documentTags) {
      final docId = shaToId[link.sha256];
      final tagId = tagByName[link.name];
      if (docId == null || tagId == null) continue;
      final key = '$docId:$tagId';
      if (!haveTag.contains(key)) {
        await _db.into(_db.documentTags).insert(
              DocumentTagsCompanion.insert(
                documentId: docId,
                tagId: tagId,
              ),
            );
      }
    }
  }

  // --- Push -----------------------------------------------------------------

  Future<({int books, int covers})> _push(
      Map<String, int> remoteBooks, Set<String> remoteCovers) async {
    var books = 0, covers = 0;
    final docs = (await _db.select(_db.documents).get())
        .where((d) => d.deletedAt == null)
        .toList();

    onStep?.call('Checking uploads…');
    for (final doc in docs) {
      final f = File(doc.storedPath);
      if (!await f.exists()) continue;
      if (!remoteBooks.keys.any((n) => _shaOf(n) == doc.sha256)) {
        onStep?.call('Uploading ${doc.title}…');
        await _dav.writeBook('${doc.sha256}__${doc.originalName}', f);
        books++;
      }
      final cover = doc.coverPath == null ? null : File(doc.coverPath!);
      if (cover != null &&
          await cover.exists() &&
          !remoteCovers.contains(doc.sha256)) {
        await _dav.writeCover(doc.sha256, await cover.readAsBytes());
        covers++;
      }
    }

    // Manifest = merged local state (post-pull), so the next device sees
    // everything this device now knows.
    final manifest = await _buildManifest();
    await _dav.writeManifest(manifest.toJson());
    return (books: books, covers: covers);
  }

  Future<SyncManifest> _buildManifest() async {
    final docs = await _db.select(_db.documents).get();
    final collections = await _db.select(_db.collections).get();
    final colById = {for (final c in collections) c.id: c.name};
    final tags = await _db.select(_db.tags).get();
    final tagById = {for (final t in tags) t.id: t.name};

    final docRows = <SyncDoc>[];
    final posRows = <SyncPosition>[];
    for (final d in docs) {
      docRows.add(SyncDoc.fromRow(d));
      final pos = await (_db.select(_db.readingPositions)
            ..where((r) => r.documentId.equals(d.id)))
          .getSingleOrNull();
      if (pos != null) posRows.add(SyncPosition.fromRow(d, pos));
    }

    final colLinks = <SyncLink>[];
    for (final j in await _db.select(_db.documentCollections).get()) {
      final sha = docs
          .where((d) => d.id == j.documentId)
          .map((d) => d.sha256)
          .firstOrNull;
      final name = colById[j.collectionId];
      if (sha != null && name != null) {
        colLinks.add(SyncLink(sha256: sha, name: name));
      }
    }
    final tagLinks = <SyncLink>[];
    for (final j in await _db.select(_db.documentTags).get()) {
      final sha = docs
          .where((d) => d.id == j.documentId)
          .map((d) => d.sha256)
          .firstOrNull;
      final name = tagById[j.tagId];
      if (sha != null && name != null) {
        tagLinks.add(SyncLink(sha256: sha, name: name));
      }
    }

    // Annotations (incl. tombstones — deletions must propagate).
    final annRows = <SyncAnnotation>[];
    for (final row in await (_db.select(_db.annotations).join([
          innerJoin(
              _db.documents, _db.documents.id.equalsExp(_db.annotations.documentId)),
        ])).get()) {
      final doc = row.readTable(_db.documents);
      final ann = row.readTable(_db.annotations);
      annRows.add(SyncAnnotation.fromRow(doc.sha256, ann));
    }

    return SyncManifest(
      documents: docRows,
      positions: posRows,
      annotations: annRows,
      collections: collections.map((c) => c.name).toList(),
      tags: tags.map((t) => t.name).toList(),
      documentCollections: colLinks,
      documentTags: tagLinks,
      syncedAt: DateTime.now(),
    );
  }

  // --- Downloads (on demand / Download-all) ---------------------------------

  /// Downloads the stored book file for [doc] if it is missing locally.
  /// Returns true when the file now exists on disk.
  Future<bool> downloadBook(Document doc,
      {void Function(int, int)? onProgress}) async {
    final f = File(doc.storedPath);
    if (await f.exists()) return true;

    final remoteBooks = await _dav.listBooks();
    final name = remoteBooks.keys.where((n) => _shaOf(n) == doc.sha256).firstOrNull;
    if (name == null) return false;

    final bytes = await _dav.readBook(name, onProgress: onProgress);
    await Directory(p.dirname(doc.storedPath)).create(recursive: true);
    await f.writeAsBytes(bytes);

    // Body extraction can now run (cloud rows were inserted pre-indexed).
    if (doc.textIndexed == 1) {
      await (_db.update(_db.documents)..where((d) => d.id.equals(doc.id)))
          .write(DocumentsCompanion(textIndexed: const Value(0)));
    }
    return true;
  }

  /// Downloads all missing book files (Settings "Download all").
  Future<int> downloadAll({void Function(String)? onStep}) async {
    var done = 0;
    final docs = (await _db.select(_db.documents).get())
        .where((d) => d.deletedAt == null)
        .toList();
    for (final doc in docs) {
      if (await File(doc.storedPath).exists()) continue;
      onStep?.call('Downloading ${doc.title}…');
      if (await downloadBook(doc)) done++;
    }
    return done;
  }

  // --- helpers --------------------------------------------------------------

  /// Empty-body FTS row keeping remote metadata searchable pre-download.
  Future<void> _upsertFtsMeta(int id, String title, String? author) =>
      _db.transaction(() async {
        await _db.customStatement(
          'DELETE FROM document_fts WHERE rowid = ?',
          [id],
        );
        await _db.customStatement(
          'INSERT INTO document_fts(rowid, title, author, body) '
          'VALUES(?, ?, ?, ?)',
          [id, title, author ?? '', ''],
        );
      });

  SyncPosition _syncPos(ReadingPosition row) => SyncPosition(
        sha256: '',
        lastPage: row.pageNumber,
        fraction: row.progress,
        location: row.location,
        updatedAt: row.updatedAt,
      );

  DocFormat _format(String name) {
    try {
      return DocFormat.values.byName(name);
    } on ArgumentError {
      return DocFormat.other;
    }
  }

  ViewerFitMode _fit(String? name) {
    try {
      return ViewerFitMode.values.byName(name ?? 'fitWidth');
    } on ArgumentError {
      return ViewerFitMode.fitWidth;
    }
  }

  ViewerColorMode _color(String? name) {
    try {
      return ViewerColorMode.values.byName(name ?? 'normal');
    } on ArgumentError {
      return ViewerColorMode.normal;
    }
  }

  static String _shaOf(String remoteName) {
    final i = remoteName.indexOf('__');
    return i <= 0 ? remoteName : remoteName.substring(0, i);
  }

  static String _origOf(String remoteName) {
    final i = remoteName.indexOf('__');
    return i < 0 || i == remoteName.length - 1
        ? remoteName
        : remoteName.substring(i + 2);
  }
}
