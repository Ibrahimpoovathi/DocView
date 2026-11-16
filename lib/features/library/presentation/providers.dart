import 'dart:async';

import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/database.dart';
import '../../../core/storage/prefs.dart';
import '../../reader/data/annotations_repository.dart';
import '../../reader/data/reading_repository.dart';
import '../data/import_service.dart';
import '../data/library_repository.dart';
import '../data/metadata_service.dart';
import '../data/text_index_repository.dart';
import '../domain/library_query.dart';

part 'providers.g.dart';

/// App-wide database (single instance for the process lifetime).
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      return NativeDatabase(File(p.join(dir.path, 'docview.sqlite')));
    }),
  );
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) =>
    LibraryRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
MetadataService metadataService(Ref ref) => MetadataService();

@Riverpod(keepAlive: true)
ImportService importService(Ref ref) => ImportService(
  ref.watch(libraryRepositoryProvider),
  ref.watch(metadataServiceProvider),
);

@Riverpod(keepAlive: true)
TextIndexRepository textIndexRepository(Ref ref) =>
    TextIndexRepository(ref.watch(appDatabaseProvider));

/// Library view state (sort/chip/search) + grid-vs-list presentation mode.
///
/// Grid/sort/chip survive cold starts via shared_preferences; the search text
/// is session-only.
@riverpod
class LibraryPrefs extends _$LibraryPrefs {
  static const _keyGrid = 'docview.lib.grid';
  static const _keySort = 'docview.lib.sort';
  static const _keyChip = 'docview.lib.chip';

  @override
  LibraryPrefsState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final sortName = prefs.getString(_keySort);
    final chipName = prefs.getString(_keyChip);
    return LibraryPrefsState(
      grid: prefs.getBool(_keyGrid) ?? true,
      sort: LibrarySort.values.firstWhere(
        (s) => s.name == sortName,
        orElse: () => LibrarySort.addedAt,
      ),
      chip: LibraryChip.values.firstWhere(
        (c) => c.name == chipName,
        orElse: () => LibraryChip.all,
      ),
    );
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  void setSort(LibrarySort sort) {
    state = state.copyWith(sort: sort);
    unawaited(_prefs.setString(_keySort, sort.name));
  }

  void setChip(LibraryChip chip) {
    state = state.copyWith(chip: chip, clearCollection: true);
    unawaited(_prefs.setString(_keyChip, chip.name));
  }

  /// Enables a collection filter (pass null to clear). Session-only: a stale
  /// id could otherwise survive the collection's deletion.
  void selectCollection(int? collectionId) {
    state = collectionId == null
        ? state.copyWith(clearCollection: true)
        : state.copyWith(collectionId: collectionId, chip: LibraryChip.all);
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }

  void toggleViewMode() {
    state = state.copyWith(grid: !state.grid);
    unawaited(_prefs.setBool(_keyGrid, state.grid));
  }
}

/// Live user collections (drives the filter chips).
final collectionsProvider = StreamProvider<List<Collection>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchCollections(),
);

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
///
/// Progress of the current multi-file import (drives the thin progress bar).
class ImportProgress {
  const ImportProgress({required this.running, this.done = 0, this.total = 0});

  const ImportProgress.idle() : running = false, done = 0, total = 0;

  final bool running;
  final int done;
  final int total;

  double? get fraction =>
      total <= 0 ? null : (done / total).clamp(0, 1).toDouble();
}

@riverpod
class ImportRunner extends _$ImportRunner {
  @override
  ImportProgress build() => const ImportProgress.idle();

  /// Returns null when import is already in progress; otherwise a summary
  /// message for the snackbar.
  Future<String?> run(List<String> paths) async {
    if (state.running) return null;
    state = ImportProgress(running: true, total: paths.length);
    try {
      final summary = await ref
          .read(importServiceProvider)
          .importSources(
            paths,
            onProgress: (done, total) {
              if (!ref.mounted) return;
              state = ImportProgress(running: true, done: done, total: total);
            },
          );
      // Kick the background FTS body indexer right after new imports.
      unawaited(ref.read(textIndexRepositoryProvider).runPending());
      return 'Imported ${summary.added}'
          ' · ${summary.duplicates} duplicates'
          '${summary.failed > 0 ? ' · ${summary.failed} failed' : ''}';
    } finally {
      state = const ImportProgress.idle();
    }
  }
}

/// Bumped when a local book copy is removed (or restored) outside the
/// documents stream, so the library re-checks which books are cloud-only.
final localCopyRevisionProvider = NotifierProvider<LocalCopyRevision, int>(
  LocalCopyRevision.new,
);

class LocalCopyRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Per-document reading positions (upsert store).
@Riverpod(keepAlive: true)
ReadingRepository readingRepository(Ref ref) =>
    ReadingRepository(ref.watch(appDatabaseProvider));

/// Per-document annotations (highlights, notes, bookmarks).
@Riverpod(keepAlive: true)
AnnotationsRepository annotationsRepository(Ref ref) =>
    AnnotationsRepository(ref.watch(appDatabaseProvider));
