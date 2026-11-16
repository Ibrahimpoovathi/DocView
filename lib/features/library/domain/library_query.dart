/// Sort orders for the library grid/list.
enum LibrarySort { lastOpened, addedAt, title, sizeBytes, format }

enum LibraryChip { all, favourites, recent }

/// Aggregate "view preferences" backing library queries.
class LibraryQuery {
  const LibraryQuery({
    this.sort = LibrarySort.addedAt,
    this.chip = LibraryChip.all,
    this.search = '',
    this.collectionId,
  });

  final LibrarySort sort;
  final LibraryChip chip;
  final String search;

  /// Optional collection filter (session-only, mutually exclusive with the
  /// favourites/recent chips).
  final int? collectionId;

  LibraryQuery copyWith({
    LibrarySort? sort,
    LibraryChip? chip,
    String? search,
    int? collectionId,
    bool clearCollection = false,
  }) =>
      LibraryQuery(
        sort: sort ?? this.sort,
        chip: chip ?? this.chip,
        search: search ?? this.search,
        collectionId: clearCollection ? null : (collectionId ?? this.collectionId),
      );
}

/// Presentation-level prefs (grid/list + query knobs) for the library screen.
class LibraryPrefsState {
  const LibraryPrefsState({
    this.grid = true,
    this.sort = LibrarySort.addedAt,
    this.chip = LibraryChip.all,
    this.search = '',
    this.collectionId,
  });

  final bool grid;
  final LibrarySort sort;
  final LibraryChip chip;
  final String search;
  final int? collectionId;

  LibraryQuery get asQuery => LibraryQuery(
        sort: sort,
        chip: chip,
        search: search,
        collectionId: collectionId,
      );

  LibraryPrefsState copyWith({
    bool? grid,
    LibrarySort? sort,
    LibraryChip? chip,
    String? search,
    int? collectionId,
    bool clearCollection = false,
  }) =>
      LibraryPrefsState(
        grid: grid ?? this.grid,
        sort: sort ?? this.sort,
        chip: chip ?? this.chip,
        search: search ?? this.search,
        collectionId:
            clearCollection ? null : (collectionId ?? this.collectionId),
      );
}
