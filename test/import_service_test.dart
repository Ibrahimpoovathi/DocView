import 'dart:io';

import 'package:docview/core/paths/app_paths.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/data/import_service.dart';
import 'package:docview/features/library/data/library_repository.dart';
import 'package:docview/features/library/data/metadata_service.dart';
import 'package:docview/features/library/domain/library_query.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late ImportService service;
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('docview-import-test');
    AppPaths.initForTest(tmp);
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
    service = ImportService(repo, MetadataService());
  });

  tearDown(() => db.close());

  test('importing the same file twice counts the second as a duplicate',
      () async {
    final source = Directory.systemTemp.createTempSync('docview-import-src');
    addTearDown(() => source.delete(recursive: true));
    final file = File('${source.path}/sample.txt')
      ..writeAsStringSync('hello world');

    final first = await service.importSources([file.path]);
    final second = await service.importSources([file.path]);

    expect(first.added, 1);
    expect(first.duplicates, 0);
    expect(second.added, 0);
    expect(second.duplicates, 1);
    expect((await repo.watchLibrary(const LibraryQuery()).first), hasLength(1));
  });

  test('two identical files in one batch import once', () async {
    final source = Directory.systemTemp.createTempSync('docview-import-src');
    addTearDown(() => source.delete(recursive: true));
    final a = File('${source.path}/a.txt')..writeAsStringSync('same bytes');
    final b = File('${source.path}/b.txt')..writeAsStringSync('same bytes');

    final summary = await service.importSources([a.path, b.path]);

    expect(summary.added, 1);
    expect(summary.duplicates, 1);
    expect(summary.failed, 0);
    expect((await repo.watchLibrary(const LibraryQuery()).first), hasLength(1));
  });

  test('unsupported extension fails without inserting a row', () async {
    final source = Directory.systemTemp.createTempSync('docview-import-src');
    addTearDown(() => source.delete(recursive: true));
    final file = File('${source.path}/nope.xyz')..writeAsStringSync('data');

    final summary = await service.importSources([file.path]);

    expect(summary.failed, 1);
    expect(summary.added, 0);
    expect(await repo.watchLibrary(const LibraryQuery()).first, isEmpty);
  });

  test('missing paths fail rather than throw', () async {
    final summary = await service.importSources(['/definitely/missing.pdf']);
    expect(summary.failed, 1);
  });
}
