import 'dart:io';
import 'dart:typed_data';

import 'package:docview/core/format/doc_format.dart';
import 'package:docview/core/paths/app_paths.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/data/library_repository.dart';
import 'package:docview/features/reader/data/txt_to_epub.dart';
import 'package:docview/features/library/domain/library_query.dart';
import 'package:docview/features/library/data/import_service.dart';
import 'package:docview/features/library/data/metadata_service.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase db;
  late LibraryRepository repo;
  late ImportService importer;
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('docview-audit-test');
    AppPaths.initForTest(tmp);
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    repo = LibraryRepository(db);
    importer = ImportService(repo, MetadataService());
  });

  tearDown(() => container.dispose());

  Future<Document> importOne(String name, Uint8List bytes) async {
    final s = await importer.importBytes({name: bytes});
    expect(s.added, 1, reason: 'expected $name to import');
    final docs = await repo.watchLibrary(const LibraryQuery()).first;
    return docs.firstWhere((d) => d.originalName == name);
  }

  test('txtToEpub handles empty and whitespace-only text', () {
    final epub = txtToEpub(Uint8List.fromList(''.codeUnits));
    expect(epub, isNotEmpty);
    final ws = txtToEpub(Uint8List.fromList('  \n\t '.codeUnits));
    expect(ws, isNotEmpty);
  });

  test('corrupt or zero-byte files import without throwing', () async {
    // Garbage PDF-shaped bytes and an empty txt must never crash the
    // import pipeline — they become ordinary rows and fail (gracefully)
    // at open time instead.
    final garbage = Uint8List.fromList(
        List.generate(64, (i) => (i * 37 + 11) & 0xFF));
    final s = await importer.importBytes(
        {'garbage.pdf': garbage, 'empty.txt': Uint8List(0)});
    expect(s.added, 2);
  });

  test('deleteDocument clears the FTS row and sets the tombstone', () async {
    final doc = await importOne(
        'delete-me.txt', Uint8List.fromList('findable body words'.codeUnits));
    await repo.deleteDocument(doc.id);
    // byId hides tombstones; raw row still exists with deletedAt set.
    final rows = await db.select(db.documents).get();
    final row = rows.firstWhere((d) => d.id == doc.id);
    expect(row.deletedAt, isNotNull);
    final hits = await repo
        .watchLibrary(const LibraryQuery(search: 'findable'))
        .first;
    expect(hits, isEmpty);
  });

  test('markOpened updates lastOpenedAt', () async {
    final doc = await importOne(
        'opened.txt', Uint8List.fromList('hello'.codeUnits));
    expect(doc.lastOpenedAt, isNull);
    await repo.markOpened(doc.id);
    final after = (await repo.byId(doc.id))!;
    expect(after.lastOpenedAt, isNotNull);
  });

  test('format detection tolerates mixed case and odd extensions', () {
    expect(DocFormat.detect('TEST.TXT'), DocFormat.txt);
    expect(DocFormat.detect('no-such-ext'), DocFormat.other);
    expect(DocFormat.detect('.odt'), DocFormat.odt);
  });

  test('watchLibrary sorts by recent only for opened docs', () async {
    final a = await importOne(
        'a.txt', Uint8List.fromList('alpha body'.codeUnits));
    final b = await importOne(
        'b.txt', Uint8List.fromList('bravo body'.codeUnits));
    await repo.markOpened(b.id);
    final docs = await repo
        .watchLibrary(const LibraryQuery(sort: LibrarySort.lastOpened))
        .first;
    expect(docs.first.id, b.id);
    expect(docs.any((d) => d.id == a.id), isTrue);
  });
}
