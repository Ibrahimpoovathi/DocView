import 'dart:io';

import 'package:docview/core/paths/app_paths.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/data/import_service.dart';
import 'package:docview/features/library/data/library_repository.dart';
import 'package:docview/features/library/domain/library_query.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:docview/features/reader/data/annotations_repository.dart';
import 'package:docview/features/reader/domain/annotations.dart';
import 'package:docview/features/reader/domain/viewer_prefs.dart';
import 'package:docview/features/sync/data/sync_engine.dart';
import 'package:docview/features/sync/data/webdav_sync.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory WebDAV double: manifest JSON + content-addressed book files.
class FakeWebdav implements WebdavBackend {
  Map<String, dynamic>? manifest;
  final Map<String, Uint8List> books = {};
  final Map<String, Uint8List> covers = {};

  @override
  Future<void> ensureDirs() async {}

  @override
  Future<Map<String, dynamic>?> readManifest() async => manifest;

  @override
  Future<void> writeManifest(Map<String, dynamic> json) async =>
      manifest = json;

  @override
  Future<Map<String, int>> listBooks() async =>
      {for (final e in books.entries) e.key: e.value.length};

  @override
  Future<Set<String>> listCoverShas() async => covers.keys.toSet();

  @override
  Future<Uint8List> readBook(String remoteName,
      {void Function(int, int)? onProgress}) async =>
      books[remoteName] ??
      (throw StateError('missing remote book $remoteName'));

  @override
  Future<void> downloadBook(String remoteName, File target,
      {void Function(int, int)? onProgress}) async {
    final bytes = await readBook(remoteName, onProgress: onProgress);
    await target.writeAsBytes(bytes);
  }

  @override
  Future<void> writeBook(String remoteName, File localFile,
      {void Function(int, int)? onProgress}) async =>
      books[remoteName] = await localFile.readAsBytes();

  @override
  Future<Uint8List?> readCover(String sha256) async => covers[sha256];

  @override
  Future<void> writeCover(String sha256, Uint8List bytes) async =>
      covers[sha256] = bytes;
}

class _Device {
  _Device(this.dav) {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(db.close);
    addTearDown(container.dispose);
    repo = container.read(libraryRepositoryProvider);
    importer = container.read(importServiceProvider);
  }

  final FakeWebdav dav;
  late final AppDatabase db;
  late final ProviderContainer container;
  late final LibraryRepository repo;
  late final ImportService importer;

  SyncEngine engine() => SyncEngine(db, dav);

  Future<Document> doc() async => db.select(db.documents).getSingle();

  /// Direct position upsert with a controllable timestamp (LWW tests).
  Future<void> putPosition(int docId, int page, DateTime updatedAt) async {
    final existing = await (db.select(db.readingPositions)
          ..where((r) => r.documentId.equals(docId)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.readingPositions).insert(
            ReadingPositionsCompanion.insert(
              documentId: docId,
              pageNumber: page,
              fitMode: ViewerFitMode.fitWidth,
              colorMode: ViewerColorMode.normal,
              updatedAt: Value(updatedAt),
            ),
          );
    } else {
      await (db.update(db.readingPositions)
            ..where((r) => r.documentId.equals(docId)))
          .write(ReadingPositionsCompanion(
        pageNumber: Value(page),
        updatedAt: Value(updatedAt),
      ));
    }
  }
}

void main() {
  late Directory tmp;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    tmp = Directory.systemTemp.createTempSync('docview-sync-test');
    AppPaths.initForTest(tmp);
  });

  _Device device(FakeWebdav dav) => _Device(dav);

  group('push + pull restore', () {
    test('device A pushes, device B pulls doc metadata + downloads', () async {
      final dav = FakeWebdav();
      final a = device(dav);

      final payload = Uint8List.fromList(List.generate(500, (i) => i % 251));
      final src = File('${tmp.path}/src-book.epub');
      await src.writeAsBytes(payload);
      final summary = await a.importer.importSources([src.path]);
      expect(summary.added, 1);

      final res = await a.engine().run();
      expect(res.uploadedBooks, 1);
      expect(dav.manifest, isNotNull);
      expect(dav.books.length, 1);
      final remoteName = dav.books.keys.single;
      final sha = remoteName.split('__').first;
      expect(sha.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sha), isTrue);
      expect(remoteName.endsWith('__src-book.epub'), isTrue);

      // Fresh device pulls: metadata row restored, no file yet (cloud doc).
      // Devices share the test tmp dir, so simulate the fresh device by
      // removing the physical file the pull is about to plan a path for.
      final aDoc0 = await a.doc();
      final plannedDir = Directory(
          '${AppPaths.booksDir.path}/${aDoc0.uuid}');
      if (await plannedDir.exists()) await plannedDir.delete(recursive: true);

      final b = device(dav);
      await b.engine().run();
      final doc = await b.doc();
      expect(doc.sha256, sha);
      final aDoc = await a.doc();
      expect(doc.uuid, aDoc.uuid); // remote uuid adopted, not regenerated
      expect(await File(doc.storedPath).exists(), isFalse);
      expect(doc.textIndexed, 1);

      // FTS row exists with empty body (metadata searchable pre-download).
      final fts = await b.db
          .customSelect('SELECT body FROM document_fts WHERE rowid = ?',
              variables: [Variable.withInt(doc.id)])
          .getSingle();
      expect(fts.data['body'], '');

      // Download lands the bytes and re-arms the body indexer.
      expect(await b.engine().downloadBook(doc), isTrue);
      expect(await File(doc.storedPath).readAsBytes(), payload);
      final refreshed = await (b.db.select(b.db.documents)
            ..where((d) => d.id.equals(doc.id)))
          .getSingle();
      expect(refreshed.textIndexed, 0);
    });

    test('second run on same device is a no-op (no duplicate uploads)', () async {
      final dav = FakeWebdav();
      final a = device(dav);
      final src = File('${tmp.path}/dup.pdf')..writeAsBytesSync([1, 2, 3, 4]);
      await a.importer.importSources([src.path]);

      await a.engine().run();
      final booksAfterFirst = Map.of(dav.books);
      final res2 = await a.engine().run();
      expect(res2.uploadedBooks, 0);
      expect(dav.books, booksAfterFirst);

      // Manifest has exactly one document.
      expect((dav.manifest!['documents'] as List), hasLength(1));
    });
  });

  group('positions LWW', () {
    test('newer remote position wins; older loses', () async {
      final dav = FakeWebdav();
      final a = device(dav);
      final src = File('${tmp.path}/pos.epub')..writeAsBytesSync(List.filled(100, 9));
      await a.importer.importSources([src.path]);
      final doc = await a.doc();

      await a.putPosition(doc.id, 3, DateTime(2026, 1, 1, 10));
      await a.engine().run(); // push position page 3

      final b = device(dav);
      await b.engine().run(); // pull position page 3
      final bPos = await b.db.select(b.db.readingPositions).getSingle();
      expect(bPos.pageNumber, 3);

      // B advances later; A syncs and must adopt B's newer state.
      final bDoc = await b.doc();
      await b.putPosition(bDoc.id, 7, DateTime(2026, 1, 1, 12));
      await b.engine().run();
      await a.engine().run();
      final aPos = await a.db.select(a.db.readingPositions).getSingle();
      expect(aPos.pageNumber, 7);

      // Older remote must NOT clobber newer local: A moves to page 5 at
      // 13:00 (newer than anything synced), then a stale page-9 manifest
      // arrives — the local 13:00 edit must survive.
      await a.putPosition(doc.id, 5, DateTime(2026, 1, 1, 13));
      final manifest = dav.manifest!;
      final positions = manifest['positions'] as List;
      positions
        ..clear()
        ..add({
          'sha256': doc.sha256,
          'lastPage': 9,
          'fraction': 0.1,
          'updatedAt': DateTime(2026, 1, 1, 11).toIso8601String(),
        });
      await a.engine().run();
      final aPos2 = await a.db.select(a.db.readingPositions).getSingle();
      expect(aPos2.pageNumber, 5);
    });
  });

  group('tombstones', () {
    test('remote deletion soft-deletes locally and drops the FTS row',
        () async {
      final dav = FakeWebdav();
      final a = device(dav);
      final src = File('${tmp.path}/doomed.txt')..writeAsBytesSync([65, 66]);
      await a.importer.importSources([src.path]);
      await a.engine().run();

      // A deletes locally and pushes the tombstone. B imported its copy
      // BEFORE the deletion so the tombstone (newer) must win under LWW.
      final b = device(dav);
      await b.importer.importSources([src.path]);
      await b.engine().run();

      final doc = await a.doc();
      await a.repo.deleteDocument(doc.id);
      await a.engine().run();
      final deleted = (dav.manifest!['documents'] as List).single;
      expect(deleted['deletedAt'], isNotNull);

      // B (doc still alive, older mutation) applies the tombstone locally.
      await b.engine().run();
      final bDoc = await b.doc();
      expect(bDoc.deletedAt, isNotNull);
      final fts = await b.db
          .customSelect('SELECT COUNT(*) c FROM document_fts WHERE rowid = ?',
              variables: [Variable.withInt(bDoc.id)])
          .getSingle();
      expect(fts.data['c'], 0);
    });

    test('fresh device pulling a tombstoned doc never shows it', () async {
      final dav = FakeWebdav();
      final a = device(dav);
      final src = File('${tmp.path}/gone.txt')..writeAsBytesSync([65]);
      await a.importer.importSources([src.path]);
      await a.repo.deleteDocument((await a.doc()).id);
      await a.engine().run();

      final b = device(dav);
      await b.engine().run();
      final rows = await b.db.select(b.db.documents).get();
      expect(rows, hasLength(1));
      expect(rows.single.deletedAt, isNotNull);
      // Soft-deleted rows are invisible to library queries.
      final visible = await b.repo.watchLibrary(const LibraryQuery()).first;
      expect(visible, isEmpty);
    });
  });

  group('collections & tags', () {
    test('names and links merge by sha256 + name', () async {
      final dav = FakeWebdav();
      final a = device(dav);
      final src = File('${tmp.path}/linked.epub')..writeAsBytesSync([1, 2, 3]);
      await a.importer.importSources([src.path]);
      final doc = await a.doc();
      final colId = await a.repo.createCollection('Work');
      await a.repo.setDocumentCollections(doc.id, {colId});
      final tagId = await a.repo.createTag('todo');
      await a.repo.setDocumentTags(doc.id, {tagId});
      await a.engine().run();

      final b = device(dav);
      await b.importer.importSources([src.path]); // same content, own uuid
      await b.engine().run();

      final bDoc = await b.doc();
      final cols = await b.repo.collectionIdsFor(bDoc.id);
      expect(cols, hasLength(1));
      final tags = await b.repo.tagIdsFor(bDoc.id);
      expect(tags, hasLength(1));
      // Names survived.
      final col = await (b.db.select(b.db.collections)
            ..where((c) => c.id.equals(cols.single)))
          .getSingle();
      expect(col.name, 'Work');
      final tag = await (b.db.select(b.db.tags)
            ..where((t) => t.id.equals(tags.single)))
          .getSingle();
      expect(tag.name, 'todo');
    });
  });

  group('annotations sync', () {
    test('device A highlights, device B restores annotation by uuid', () async {
      final dav = FakeWebdav();
      final a = device(dav);
      final src = File('${tmp.path}/annot.epub')..writeAsBytesSync([1, 2, 3]);
      await a.importer.importSources([src.path]);
      final doc = await a.doc();
      final annRepo = AnnotationsRepository(a.db);
      await annRepo.create(
        doc.id,
        kind: AnnotationKind.highlight,
        anchor: AnnotationAnchor(cfi: 'epubcfi(/6/2!4:0-4:9)'),
        excerpt: 'silver ribbons',
        color: 'yellow',
      );
      await a.engine().run();

      final b = device(dav);
      await b.importer.importSources([src.path]);
      await b.engine().run();
      final bDoc = await b.doc();
      final rows = await AnnotationsRepository(b.db).listForDoc(bDoc.id);
      expect(rows, hasLength(1));
      expect(rows.single.kind, AnnotationKind.highlight);
      expect(rows.single.excerpt, 'silver ribbons');
      expect(rows.single.color, 'yellow');

      // Deleting on A propagates as a tombstone to B.
      await annRepo.softDelete((await annRepo.listForDoc(doc.id)).first.id);
      await a.engine().run();
      await b.engine().run();
      final bRows = await AnnotationsRepository(b.db).listForDoc(bDoc.id);
      expect(bRows, isEmpty);
      final raw = await (b.db.select(b.db.annotations)
            ..where((x) => x.documentId.equals(bDoc.id)))
          .getSingle();
      expect(raw.deletedAt, isNotNull);
    });

    test('newer remote annotation wins; same-second tie stays local', () async {
      final dav = FakeWebdav();
      final a = device(dav);
      final src = File('${tmp.path}/lww.epub')..writeAsBytesSync([1, 2, 3]);
      await a.importer.importSources([src.path]);
      final doc = await a.doc();

      // Remote manifest: a newer annotation for the same doc, plus a
      // same-second tie with different content.
      // Same-second tie (Drift stores DateTime at second precision): floor
      // to whole seconds so both sides serialize identically.
      final tieTime = DateTime.fromMillisecondsSinceEpoch(
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000);
      final note = AnnotationsRepository(a.db);
      final local = await note.create(
        doc.id,
        kind: AnnotationKind.note,
        anchor: AnnotationAnchor(cfi: 'epubcfi(/6/2!4:0)'),
        note: 'keep me',
        createdAt: tieTime,
      );
      // Force the same updatedAt second (Drift stores DateTime at seconds).
      await (a.db.update(a.db.annotations)
            ..where((x) => x.id.equals(local.id)))
          .write(AnnotationsCompanion(
        updatedAt: Value(tieTime),
      ));

      final manifest = {
        'version': 2,
        'documents': [
          {
            'sha256': doc.sha256,
            'uuid': doc.uuid,
            'title': doc.title,
            'format': 'epub',
            'favourite': false,
            'addedAt': doc.addedAt.toIso8601String(),
          }
        ],
        'positions': <Object?>[],
        'annotations': [
          {
            'uuid': local.uuid,
            'sha256': doc.sha256,
            'kind': 'note',
            'anchor': '{"cfi":"epubcfi(/6/2!8:0)"}',
            'note': 'overwrite attempt',
            'updatedAt': tieTime.toIso8601String(),
          },
          {
            'uuid': 'remote-newer',
            'sha256': doc.sha256,
            'kind': 'highlight',
            'anchor': '{"cfi":"epubcfi(/6/2!12:0-12:6)"}',
            'color': 'green',
            'updatedAt':
                tieTime.add(const Duration(seconds: 5)).toIso8601String(),
          },
        ],
        'collections': <Object?>[],
        'tags': <Object?>[],
        'documentCollections': <Object?>[],
        'documentTags': <Object?>[],
      };
      dav.manifest = manifest;
      await a.engine().run();

      final rows = await AnnotationsRepository(a.db).listForDoc(doc.id);
      // Tie kept the local note; the strictly-newer remote highlight landed.
      expect(
        rows.map((r) => r.note ?? r.excerpt),
        contains('keep me'),
      );
      expect(rows.where((r) => r.kind == AnnotationKind.highlight),
          hasLength(1));
      expect(
        rows.where((r) => r.kind == AnnotationKind.note).single.note,
        'keep me',
      );
    });
  });
}
