import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/database.dart';
import '../../reader/data/reading_repository.dart';
import '../data/import_service.dart';
import '../data/library_repository.dart';
import '../data/metadata_service.dart';
import '../domain/library_query.dart';

part 'providers.g.dart';

/// App-wide database (single instance for the process lifetime).
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    return NativeDatabase(File(p.join(dir.path, 'docview.sqlite')));
  }));
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) =>
    LibraryRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
MetadataService metadataService(Ref ref) => MetadataService();

@Riverpod(keepAlive: true)
ImportService importService(Ref ref) =>
    ImportService(ref.watch(libraryRepositoryProvider), ref.watch(metadataServiceProvider));

/// Library view state (sort/chip/search) + grid-vs-list presentation mode.
@riverpod
class LibraryPrefs extends _$LibraryPrefs {
  @override
  LibraryPrefsState build() => const LibraryPrefsState();

  void setSort(LibrarySort sort) {
    state = state.copyWith(sort: sort);
  }

  void setChip(LibraryChip chip) {
    state = state.copyWith(chip: chip);
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }

  void toggleViewMode() {
    state = state.copyWith(grid: !state.grid);
  }
}


/// Live documents stream honoring the current prefs.
/// Manual providers: riverpod_generator 4.x cannot resolve drift data-class
/// generics (`Stream<List<Document>>`) in codegen function providers.
final libraryDocsProvider = StreamProvider<List<Document>>((ref) {
  final prefs = ref.watch(libraryPrefsProvider);
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchLibrary(prefs.asQuery);
});

/// Continue-reading shelf stream.
final continueReadingProvider = StreamProvider<List<Document>>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchContinueReading();
});

/// Import run state for UI feedback.
@riverpod
class ImportRunner extends _$ImportRunner {
  @override
  String build() => '';

  /// Returns null when import is already in progress; otherwise a summary
  /// message for the snackbar.
  Future<String?> run(List<String> paths) async {
    if (state == importing) return null;
    state = importing;
    try {
      final summary = await ref.read(importServiceProvider).importSources(paths);
      return 'Imported ${summary.added}'
          ' · ${summary.duplicates} duplicates'
          '${summary.failed > 0 ? ' · ${summary.failed} failed' : ''}';
    } finally {
      state = '';
    }
  }

  static const importing = 'importing';
}

/// Per-document reading positions (upsert store).
@Riverpod(keepAlive: true)
ReadingRepository readingRepository(Ref ref) =>
    ReadingRepository(ref.watch(appDatabaseProvider));
