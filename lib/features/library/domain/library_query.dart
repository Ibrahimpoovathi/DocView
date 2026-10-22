/// Sort orders for the library grid/list.
enum LibrarySort { lastOpened, addedAt, title, sizeBytes, format }

enum LibraryChip { all, favourites, recent }

/// Aggregate "view preferences" backing library queries.
class LibraryQuery {
  const LibraryQuery({
    this.sort = LibrarySort.addedAt,
    this.chip = LibraryChip.all,
    this.search = '',
  });

  final LibrarySort sort;
  final LibraryChip chip;
  final String search;

  LibraryQuery copyWith({
    LibrarySort? sort,
    LibraryChip? chip,
    String? search,
  }) =>
      LibraryQuery(
        sort: sort ?? this.sort,
        chip: chip ?? this.chip,
        search: search ?? this.search,
      );
}

/// Presentation-level prefs (grid/list + query knobs) for the library screen.
class LibraryPrefsState {
  const LibraryPrefsState({
    this.grid = true,
    this.sort = LibrarySort.addedAt,
    this.chip = LibraryChip.all,
    this.search = '',
  });

  final bool grid;
  final LibrarySort sort;
  final LibraryChip chip;
  final String search;

  LibraryQuery get asQuery =>
      LibraryQuery(sort: sort, chip: chip, search: search);

  LibraryPrefsState copyWith({
    bool? grid,
    LibrarySort? sort,
    LibraryChip? chip,
    String? search,
  }) =>
      LibraryPrefsState(
        grid: grid ?? this.grid,
        sort: sort ?? this.sort,
        chip: chip ?? this.chip,
        search: search ?? this.search,
      );
}
