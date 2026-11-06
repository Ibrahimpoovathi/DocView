import 'package:docview/core/storage/database.dart';
import 'package:docview/features/reader/data/reading_repository.dart';
import 'package:docview/features/reader/domain/viewer_prefs.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late ReadingRepository repo;

  setUp(() {
    final db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      db.close();
      container.dispose();
    });
    repo = container.read(readingRepositoryProvider);
  });

  test('ensure creates row once, keeps numbering across calls', () async {
    final a = await repo.ensure(7);
    final b = await repo.ensure(7);
    expect(a.pageNumber, 1);
    expect(b.pageNumber, 1);
    expect(a.fitMode, ViewerFitMode.fitWidth);
    expect(b.documentId, a.documentId);
  });

  test('savePage upserts position and updatedAt', () async {
    await repo.ensure(3);
    await repo.savePage(3, 42);
    final pos = await repo.forDoc(3);
    expect(pos!.pageNumber, 42);
    await repo.savePage(3, 43);
    expect((await repo.forDoc(3))!.pageNumber, 43);
  });

  test('savePrefs stores color mode', () async {
    await repo.ensure(1);
    await repo.savePrefs(1, colorMode: ViewerColorMode.sepia);
    expect((await repo.forDoc(1))!.colorMode, ViewerColorMode.sepia);
  });

  test('forDoc returns null for unknown doc', () async {
    expect(await repo.forDoc(99), isNull);
  });
}
