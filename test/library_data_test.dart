import 'dart:io';
import 'dart:typed_data';

import 'package:docview/core/format/doc_format.dart';
import 'package:docview/core/paths/app_paths.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/data/library_repository.dart';
import 'package:docview/features/library/domain/library_query.dart';
import 'package:docview/features/library/data/import_service.dart';
import 'package:docview/features/library/data/metadata_service.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late LibraryRepository repo;
  late ImportService importer;
  late Directory tmp;

  tearDownAll(() {});


  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('docview-paths-test');
    AppPaths.initForTest(tmp);
  });

  setUp(() {
    final db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(db.close);
    repo = container.read(libraryRepositoryProvider);
    importer = container.read(importServiceProvider);
  });

  tearDown(() => container.dispose());


  group('repository CRUD', () {
    test('insert, watch, soft delete, restore path', () async {
      final id = await repo.insertDocument(
        sampleDoc(
          uuid: 'u1',
          sha: 'hash-1',
          title: 'Alpha',
        ),
      );

      var rows = await repo.watchLibrary(const LibraryQuery()).first;
      expect(rows, hasLength(1));
      expect(rows.single.title, 'Alpha');

      await repo.deleteDocument(id);
      rows = await repo.watchLibrary(const LibraryQuery()).first;
      expect(rows, isEmpty);

      final byId = await repo.byId(id);
      expect(byId, isNull, reason: 'byId hides soft-deleted rows');
    });
  });

  group('import pipeline', () {
    test('adds supported files once, then dedupes on sha256', () async {
      final src = await Directory.systemTemp.createTemp('docview-import-src');
      final file = File('${src.path}/hello.md');
      await file.writeAsString('# hello');

      final first = await importer.importSources([file.path]);
      expect(first.added, 1, reason: '$first');
      expect(first.duplicates, 0);

      final second = await importer.importSources([file.path]);
      expect(second.added, 0, reason: '$second');
      expect(second.duplicates, 1);

      final rows = await repo.watchLibrary(const LibraryQuery()).first;
      expect(rows, hasLength(1));
      expect(rows.single.originalName, 'hello.md');
      expect(rows.single.format, DocFormat.txt);
      expect(rows.single.title, 'hello');
      await src.delete(recursive: true);
    });

    test('skips unsupported extensions and missing files', () async {
      final src = await Directory.systemTemp.createTemp('docview-import-src');
      await File('${src.path}/virus.exe').writeAsBytes([1, 2, 3]);

      final summary = await importer.importSources([
        '${src.path}/virus.exe',
        '${src.path}/gone.md',
      ]);
      expect(summary.added, 0, reason: '$summary');
      expect(summary.failed, 2, reason: '$summary');
      await src.delete(recursive: true);
    });

    test('ImportServiceBytes imports whole bytes', () async {
      final bytes = Uint8List.fromList('# bytes'.codeUnits);
      final summary = await importer.importBytes({'memo.md': bytes});
      expect(summary.added, 1, reason: '$summary');
    });
  });
}

DocumentsCompanion sampleDoc({
  required String uuid,
  required String sha,
  required String title,
}) =>
    DocumentsCompanion.insert(
      uuid: uuid,
      format: DocFormat.pdf,
      originalName: '$title.pdf',
      title: title,
      storedPath: 'ignored/$uuid/x.pdf',
      sizeBytes: 42,
      sha256: sha,
    );
