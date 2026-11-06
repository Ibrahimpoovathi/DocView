import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/design/dv.dart';
import '../../../core/design/widgets/doc_card.dart';
import '../../../core/design/widgets/empty_state.dart';
import '../../../core/design/widgets/shelf_bar.dart';
import '../../../core/design/widgets/skeleton.dart';
import '../../../core/storage/database.dart';
import '../domain/library_query.dart';
import '../data/import_service.dart';
import 'doc_options_sheet.dart';
import 'providers.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    if (batteryHook) unawaited(_batterySeed());
  }

  /// Battery hook (debug-define builds only): import the bundled mini PDF
  /// through the real pipeline and deep-open its reader.
  Future<void> _batterySeed() async {
    final data = await rootBundle.load('assets/battery/mini.pdf');
    final summary =
        await ref.read(importServiceProvider).importBytes(
              {'mini.pdf': data.buffer.asUint8List()},
            );
    if (summary.added != 1) return;
    final docs = await ref
        .read(libraryRepositoryProvider)
        .watchLibrary(const LibraryQuery())
        .first;
    final doc = docs.isEmpty ? null : docs.first;
    if (!mounted || doc == null) return;
    await context.push('/reader/${doc.id}');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _import({bool asFolder = false}) async {
    List<String> paths;
    if (asFolder) {
      final dirPath = await fp.FilePicker.getDirectoryPath(
        dialogTitle: 'Import a folder of documents',
      );
      if (dirPath == null) return;
      final dir = Directory(dirPath);
      final entities = dir.listSync(recursive: false);
      paths = entities
          .whereType<File>()
          .map((f) => f.path)
          .toList();
    } else {
      paths = await fp.FilePicker.pickFileAndDirectoryPaths(
        dialogTitle: 'Add documents',
        type: fp.FileType.custom,
        allowedExtensions: [
          'pdf', 'epub', 'docx', 'docm', 'xlsx', 'xlsm', 'pptx', 'pptm',
          'txt', 'text', 'md', 'cbz', 'mobi', 'prc', 'azw3', 'kfx', 'fb2',
          'rtf', 'doc', 'odt',
        ],
      );
    }
    if (!mounted || paths.isEmpty) return;
    final message = await ref.read(importRunnerProvider.notifier).run(paths);
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _openDoc(Document doc) {
    ref.read(libraryRepositoryProvider).markOpened(doc.id);
    context.push('/reader/${doc.id}');
  }

  void _docMenu(Document doc) =>
      showDocOptionsSheet(context, ref, doc);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final prefs = ref.watch(libraryPrefsProvider);
    final prefsN = ref.read(libraryPrefsProvider.notifier);

    final docsAsync = ref.watch(libraryDocsProvider);
    final shelfAsync = ref.watch(continueReadingProvider);

    final body = docsAsync.when(
      data: (docs) {
        final shelf = shelfAsync.value ?? const <Document>[];

        if (docs.isEmpty && prefs.search.isEmpty) {
          return _EmptyLibrary(
            onImport: () => _import(),
          );
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: shelf.isEmpty
                  ? const SizedBox(height: Dv.sp8)
                  : ShelfBar(
                      documents: shelf,
                      onOpen: _openDoc,
                      onLongPress: _docMenu,
                    ),
            ),
            const SliverToBoxAdapter(child: _ChipRow()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp8, Dv.sp20, Dv.sp8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(
                      _sectionTitle(prefs.chip, docs.length),
                      style: text.headlineMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: prefs.grid ? 'List view' : 'Grid view',
                      onPressed: prefsN.toggleViewMode,
                      icon: Icon(
                        prefs.grid
                            ? Icons.view_headline_rounded
                            : Icons.grid_view_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    _SortMenu(current: prefs.sort, onPick: prefsN.setSort),
                  ],
                ),
              ),
            ),
            if (docs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.manage_search_rounded,
                  heading: 'Nothing here',
                  body: 'Try a different search or filter.',
                ),
              )
            else
              prefs.grid
                  ? _ResponsiveGrid(
                      docs: docs,
                      onOpen: _openDoc,
                      onLongPress: _docMenu,
                    )
                  : _DocList(
                      docs: docs,
                      onOpen: _openDoc,
                      onLongPress: _docMenu,
                    ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 96),
            ),
          ],
        );
      },
      loading: () => const _LibrarySkeleton(),
      error: (e, s) => EmptyState(
        icon: Icons.error_outline_rounded,
        heading: 'Something went wrong',
        body: '$e',
      ),
    );

    return Scaffold(
      appBar: _Bar(
        searchOpen: _searchOpen,
        searchCtrl: _searchCtrl,
        onToggleSearch: () => setState(() {
          if (_searchOpen) {
            _searchCtrl.clear();
            prefsN.setSearch('');
          }
          _searchOpen = !_searchOpen;
        }),
        onSearch: prefsN.setSearch,
        onImport: () => _import(),
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(),
        icon: const Icon(Icons.file_open_rounded),
        label: const Text('Add documents'),
      ),
      endDrawer: _ToolsDrawer(
        onImportFiles: () {
          Navigator.pop(context);
          _import();
        },
        onImportFolder: () {
          Navigator.pop(context);
          _import(asFolder: true);
        },
      ),
    );
  }

  String _sectionTitle(LibraryChip chip, int count) => switch (chip) {
        LibraryChip.favourites => 'Bookmarks',
        LibraryChip.recent => 'Recently opened',
        LibraryChip.all => 'Library · $count',
      };
}

// --- App bar ----------------------------------------------------------------

class _Bar extends StatelessWidget implements PreferredSizeWidget {
  const _Bar({
    required this.searchOpen,
    required this.searchCtrl,
    required this.onToggleSearch,
    required this.onSearch,
    required this.onImport,
  });

  final bool searchOpen;
  final TextEditingController searchCtrl;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearch;
  final VoidCallback onImport;

  @override
  Size get preferredSize =>
      Size.fromHeight(searchOpen ? 116 : 64);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dv.sp20),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: Dv.settle,
                    switchInCurve: Dv.settleCurve,
                    child: searchOpen
                        ? Text(
                            'Search',
                            key: const ValueKey('s'),
                            style: text.headlineMedium
                                ?.copyWith(fontSize: 22),
                          )
                        : Text('DocView',
                            key: const ValueKey('d'),
                            style: text.displaySmall?.copyWith(fontSize: 27)),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: onToggleSearch,
                    icon: Icon(
                      searchOpen ? Icons.close_rounded : Icons.search_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Builder(builder: (ctx) {
                    return IconButton(
                      tooltip: 'Tools',
                      onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          if (searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(Dv.sp20, 0, Dv.sp20, Dv.sp8),
              child: TextField(
                controller: searchCtrl,
                autofocus: true,
                onChanged: onSearch,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search titles, authors, file names',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Chips ------------------------------------------------------------------

class _ChipRow extends ConsumerWidget {
  const _ChipRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(libraryPrefsProvider);
    final n = ref.read(libraryPrefsProvider.notifier);
    return SizedBox(
      height: 44,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Dv.sp20),
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            context,
            'All',
            LibraryChip.all,
            prefs.chip,
            (c) => n.setChip(c),
          ),
          const SizedBox(width: Dv.sp8),
          _chip(
            context,
            'Bookmarks',
            LibraryChip.favourites,
            prefs.chip,
            (c) => n.setChip(c),
          ),
          const SizedBox(width: Dv.sp8),
          _chip(
            context,
            'Recent',
            LibraryChip.recent,
            prefs.chip,
            (c) => n.setChip(c),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    LibraryChip value,
    LibraryChip current,
    ValueChanged<LibraryChip> onSelect,
  ) =>
      FilterChip(
        label: Text(label),
        selected: value == current,
        onSelected: (_) => onSelect(value),
      );
}

// --- Sort menu --------------------------------------------------------------

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.current, required this.onPick});

  final LibrarySort current;
  final ValueChanged<LibrarySort> onPick;

  static const _labels = {
    LibrarySort.addedAt: 'Recently added',
    LibrarySort.lastOpened: 'Last opened',
    LibrarySort.title: 'Title A–Z',
    LibrarySort.sizeBytes: 'Largest first',
    LibrarySort.format: 'By format',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Sort',
      onSelected: onPick,
      icon: Icon(Icons.sort_rounded, color: cs.onSurfaceVariant),
      itemBuilder: (ctx) => _labels.entries
          .map((e) => PopupMenuItem<LibrarySort>(
                value: e.key,
                child: Row(
                  children: [
                    if (e.key == current)
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: cs.primary,
                      )
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: Dv.sp8),
                    Text(e.value),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// --- Grid / list ------------------------------------------------------------

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.docs,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<Document> docs;
  final void Function(Document) onOpen;
  final void Function(Document) onLongPress;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxis = (width / 176).clamp(2, 6).toDouble().toInt();
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Dv.sp20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxis,
          mainAxisSpacing: Dv.sp16,
          crossAxisSpacing: Dv.sp16,
          mainAxisExtent: 258,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _Staggered(
            index: i,
            child: DocCard(
              document: docs[i],
              onOpen: () => onOpen(docs[i]),
              onLongPress: () => onLongPress(docs[i]),
            ),
          ),
          childCount: docs.length,
        ),
      ),
    );
  }
}

class _DocList extends StatelessWidget {
  const _DocList({
    required this.docs,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<Document> docs;
  final void Function(Document) onOpen;
  final void Function(Document) onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Dv.sp20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final d = docs[i];
            return _Staggered(
              index: i,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Dv.sp8),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Dv.rLg),
                    onTap: () => onOpen(d),
                    onLongPress: () => onLongPress(d),
                    child: Padding(
                      padding: const EdgeInsets.all(Dv.sp12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: d.coverPath != null
                                ? Image.file(
                                    File(d.coverPath!),
                                    width: 44,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => _listPh(cs),
                                  )
                                : _listPh(cs),
                          ),
                          const SizedBox(width: Dv.sp12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium
                                      ?.copyWith(fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${d.format.label}'
                                  '${d.author == null ? '' : ' · ${d.author}'}',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (d.isFavourite)
                            Icon(
                              Icons.bookmark_added_rounded,
                              size: 18,
                              color: cs.tertiary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: docs.length,
        ),
      ),
    );
  }

  Widget _listPh(ColorScheme cs) => Container(
        width: 44,
        height: 60,
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.menu_book_rounded,
            size: 20, color: cs.onPrimaryContainer.withValues(alpha: 0.5)),
      );
}

class _Staggered extends StatefulWidget {
  const _Staggered({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_Staggered> createState() => _StaggeredState();
}

class _StaggeredState extends State<_Staggered>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Dv.entrance,
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_runOnce) {
      _runOnce = true;
      Future.delayed(
        Dv.stagger * widget.index.clamp(0, 20),
        () {
          if (mounted) _ctrl.forward(from: 0);
        },
      );
    }
  }

  bool _runOnce = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: CurvedAnimation(
          parent: _ctrl,
          curve: Curves.easeOutCubic,
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
          ),
          child: widget.child,
        ),
      );
}

// --- Skeleton / drawer ------------------------------------------------------

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxis = (width / 176).clamp(2, 6).toDouble().toInt();
    return GridView.count(
      crossAxisCount: crossAxis,
      padding: const EdgeInsets.all(Dv.sp20),
      mainAxisSpacing: Dv.sp16,
      crossAxisSpacing: Dv.sp16,
      childAspectRatio: 176 / 304,
      children: List.generate(crossAxis * 3, (i) => const SkeletonDocCard()),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.auto_stories_rounded,
      heading: 'Your library is empty',
      body: 'Add PDF, EPUB, Office documents and more to start reading.',
      actionLabel: 'Pick files',
      onAction: onImport,
    );
  }
}

class _ToolsDrawer extends StatelessWidget {
  const _ToolsDrawer({
    required this.onImportFiles,
    required this.onImportFolder,
  });

  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Drawer(
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(Dv.rXl)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Dv.sp16),
          children: [
            Padding(
              padding: const EdgeInsets.all(Dv.sp8),
              child: Text('Tools', style: text.titleLarge),
            ),
            const SizedBox(height: Dv.sp8),
            DvSheetTile(
              icon: Icons.file_open_rounded,
              label: 'Import files…',
              onTap: onImportFiles,
            ),
            DvSheetTile(
              icon: Icons.folder_open_outlined,
              label: 'Import folder…',
              onTap: onImportFolder,
            ),
            const Divider(),
            DvSheetTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
