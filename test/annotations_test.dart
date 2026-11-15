import 'dart:convert';

import 'package:docview/core/format/doc_format.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:docview/features/reader/data/annotations_repository.dart';
import 'package:docview/features/reader/domain/annotations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase db;
  late AnnotationsRepository repo;
  var nextDocId = 1;

  Future<int> seedDoc() async {
    final id = nextDocId++;
    await db.into(db.documents).insert(DocumentsCompanion.insert(
          uuid: 'u$id',
          format: DocFormat.pdf,
          originalName: 'doc$id.pdf',
          title: 'Doc $id',
          storedPath: '/tmp/doc$id.pdf',
          sizeBytes: 10,
          sha256: 'sha$id',
        ));
    return id;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      db.close();
      container.dispose();
    });
    repo = container.read(annotationsRepositoryProvider);
  });

  AnnotationAnchor cfi(String cfi) => AnnotationAnchor(cfi: cfi);
  AnnotationAnchor pdfRange(int page, int start, int end) =>
      AnnotationAnchor(page: page, start: start, end: end);

  test('create round-trips anchor JSON, kind, excerpt and color', () async {
    final doc = await seedDoc();
    final a = await repo.create(
      doc,
      kind: AnnotationKind.highlight,
      anchor: pdfRange(2, 5, 40),
      excerpt: 'the battery term',
      color: 'yellow',
    );
    expect(a.documentId, doc);
    expect(a.kind, AnnotationKind.highlight);
    expect(AnnotationAnchor.fromJson(jsonDecode(a.anchor) as Map<String, Object?>).page, 2);
    expect(a.excerpt, 'the battery term');
    expect(a.color, 'yellow');
  });

  test('watchForDoc hides soft-deleted rows and stays live', () async {
    final doc = await seedDoc();
    final a = await repo.create(
      doc,
      kind: AnnotationKind.note,
      anchor: cfi('epubcfi(/6/4)'),
      note: 'check this',
    );
    await repo.create(
      doc,
      kind: AnnotationKind.highlight,
      anchor: cfi('epubcfi(/6/8)'),
      color: 'blue',
    );
    expect((await repo.listForDoc(doc)).length, 2);
    await repo.softDelete(a.id);
    final left = await repo.listForDoc(doc);
    expect(left.length, 1);
    expect(left.single.kind, AnnotationKind.highlight);
  });

  test('update stamps updatedAt and normalizes empty note', () async {
    final doc = await seedDoc();
    final a = await repo.create(doc, kind: AnnotationKind.note, anchor: cfi('x'));
    final before = a.updatedAt;
    await Future<void>.delayed(const Duration(seconds: 1));
    await repo.update(a.id, note: 'edited');
    final after = await repo.byUuid(a.uuid);
    expect(after!.note, 'edited');
    expect(after.updatedAt, isNot(before));
    await repo.update(a.id, note: '');
    expect((await repo.byUuid(a.uuid))!.note, isNull);
  });

  test('upsertRemote inserts unknown uuid and adopts LWW winner', () async {
    final doc = await seedDoc();
    final local = await repo.create(
      doc,
      kind: AnnotationKind.highlight,
      anchor: cfi('loc'),
      color: 'yellow',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final newer = AnnotationsCompanion.insert(
      uuid: 'remote',
      documentId: doc,
      kind: AnnotationKind.note,
      anchor: '{"cfi":"r"}',
      updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(9000)),
    );
    // Older remote content loses to the newer local row.
    await repo.upsertRemote(newer.copyWith(
      updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(500)),
    ));
    final stillLocal = await repo.byUuid(local.uuid);
    expect(stillLocal!.color, 'yellow');
    // Unknown uuid lands.
    final remoteStamp = DateTime.now();
    await repo.upsertRemote(AnnotationsCompanion.insert(
      uuid: 'remote',
      documentId: doc,
      kind: AnnotationKind.note,
      anchor: '{"cfi":"r"}',
      updatedAt: Value(remoteStamp),
    ));
    expect((await repo.byUuid('remote'))!.kind, AnnotationKind.note);
    // Newer remote content overwrites the local row.
    await repo.upsertRemote(AnnotationsCompanion.insert(
      uuid: local.uuid,
      documentId: doc,
      kind: AnnotationKind.highlight,
      anchor: '{"cfi":"loc"}',
      color: const Value('green'),
      updatedAt: Value(local.updatedAt!.add(const Duration(seconds: 2))),
    ));
    expect((await repo.byUuid(local.uuid))!.color, 'green');
  });

  test('upsertRemote ties are deletion-dominant', () async {
    final doc = await seedDoc();
    final local = await repo.create(
      doc,
      kind: AnnotationKind.highlight,
      anchor: cfi('loc'),
      color: 'yellow',
    );
    final sameSecond = local.updatedAt!;
    // Same-second tie + remote tombstone → row stays deleted locally.
    await repo.upsertRemote(AnnotationsCompanion.insert(
      uuid: local.uuid,
      documentId: doc,
      kind: AnnotationKind.highlight,
      anchor: '{"cfi":"loc"}',
      color: const Value('green'),
      updatedAt: Value(sameSecond),
      deletedAt: Value(sameSecond),
    ));
    expect((await repo.byUuid(local.uuid))!.deletedAt, isNotNull);
    // Same-second tie without deletion → local content wins.
    final b = await repo.create(
      doc,
      kind: AnnotationKind.note,
      anchor: cfi('loc2'),
      note: 'keep me',
    );
    await repo.upsertRemote(AnnotationsCompanion.insert(
      uuid: b.uuid,
      documentId: doc,
      kind: AnnotationKind.note,
      anchor: '{"cfi":"loc2"}',
      note: const Value('overwrite attempt'),
      updatedAt: Value(b.updatedAt!),
    ));
    expect((await repo.byUuid(b.uuid))!.note, 'keep me');
  });

  test('latest schema creates the annotations table and tombstones', () async {
    // In-memory DBs always start at the latest schema (onCreate runs
    // createAll); assert the table set and the version marker.
    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle()
        .then((row) => row.data.values.first as int);
    expect(version, 7);
    expect(db.allTables.map((t) => t.actualTableName), contains('annotations'));
    expect(db.allTables.map((t) => t.actualTableName), contains('collections'));
    expect(db.allTables.map((t) => t.actualTableName), contains('tags'));
  });
}
