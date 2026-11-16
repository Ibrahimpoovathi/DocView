import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/design/dv.dart';
import '../../../core/design/widgets/doc_card.dart';
import '../../../core/design/widgets/empty_state.dart';
import '../../../core/design/widgets/shelf_bar.dart';
import '../../../core/design/widgets/skeleton.dart';
import '../../../core/platform/open_with.dart';
import '../../../core/storage/database.dart';
import '../domain/library_query.dart';
import '../data/battery_seeder.dart';
import '../../sync/data/webdav_sync.dart';
import '../../sync/presentation/sync_providers.dart';
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
  StreamSubscription<OpenWithFile>? _openWithSub;

  // Cloud-only doc ids (file missing). Computed once per docs-list emission —
  // never synchronously inside build — so large libraries stay jank-free.
  List<Document>? _checkedDocs;
  int _checkedRevision = -1;
  Set<int> _cloudOnly = const <int>{};

  void _scheduleCloudCheck(List<Document> docs, int revision) {
    if (identical(docs, _checkedDocs) && revision == _checkedRevision) return;
    _checkedDocs = docs;
    _checkedRevision = revision;
    unawaited(_computeCloudOnly(docs));
  }

  Future<void> _computeCloudOnly(List<Document> docs) async {
    final missing = <int>{};
    for (var i = 0; i < docs.length; i++) {
      if (!File(docs[i].storedPath).existsSync()) missing.add(docs[i].id);
      // Yield between batches so a huge library never blocks a frame.
      if (i % 50 == 49) await Future<void>.delayed(Duration.zero);
    }
    if (!mounted || !identical(docs, _checkedDocs)) return;
    if (const SetEquality<int>().equals(missing, _cloudOnly)) return;
    setState(() => _cloudOnly = missing);
  }

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(textIndexRepositoryProvider).runPending());
    // Finish cleanup for documents whose undo window was interrupted by a
    // crash/kill (safe and idempotent).
    unawaited(
      ref
          .read(libraryRepositoryProvider)
          .purgeAbandonedArtifacts()
          .catchError((Object _) {}),
    );
    unawaited(OpenWith.instance.start());
    _openWithSub = OpenWith.instance.files.listen(_openSharedFile);
    if (batteryHook) {
      final seeder = BatterySeeder(ref);
      unawaited(() async {
        final next = batteryEdgeUrl.isNotEmpty
            ? await seeder.edgeImport()
            : await seeder.seed();
        if (next != null && mounted) {
          await context.push('/reader/${next.id}');
        }
      }());
    }
    // Battery sync: configure the account from the define, then boot-sync
    // (push on a data device, pull/restore on a cleared one). Setup must
    // complete before autoSync reads the account store — unawaited setup
    // racing autoSync made the first boot skip the push.
    if (batteryHook && batterySyncUrl.isNotEmpty) {
      unawaited(_batterySyncSetup().then((_) => _autoSync()));
    } else {
      // Auto-sync on boot (only when a WebDAV account is configured).
      unawaited(_autoSync());
    }
    if (batteryHook && batterySearchTerm.isNotEmpty) {
      // Battery: exercise the FTS library-search path end to end.
      setState(() {
        _searchOpen = true;
        _searchCtrl.text = batterySearchTerm;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(libraryPrefsProvider.notifier).setSearch(batterySearchTerm);
        }
      });
    }
  }

  @override
  void dispose() {
    _openWithSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Imports a file handed over by another app, then opens it.
  Future<void> _openSharedFile(OpenWithFile shared) async {
    String? error;
    try {
      final doc = await ref
          .read(importServiceProvider)
          .importDocument(shared.path);
      if (doc == null) {
        error = 'Could not open "${shared.name}" — unsupported or unreadable.';
      } else {
        unawaited(ref.read(textIndexRepositoryProvider).runPending());
        ref.read(libraryRepositoryProvider).markOpened(doc.id);
        if (mounted) context.push('/reader/${doc.id}');
      }
    } on Object catch (e) {
      error = 'Could not open "${shared.name}": $e';
    } finally {
      if (shared.temporary) {
        try {
          final copy = File(shared.path);
          if (await copy.exists()) await copy.delete();
        } on FileSystemException {
          // Cache cleanup is best-effort.
        }
      }
    }
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _showTools() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
      ),
      builder: (sheetCtx) => _ToolsSheet(
        onImportFiles: () {
          Navigator.pop(sheetCtx);
          _import();
        },
        onImportFolder: () {
          Navigator.pop(sheetCtx);
          _import(asFolder: true);
        },
        onSyncNow: () {
          Navigator.pop(sheetCtx);
          _syncNow();
        },
      ),
    );
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
      paths = entities.whereType<File>().map((f) => f.path).toList();
    } else {
      paths = await fp.FilePicker.pickFileAndDirectoryPaths(
        dialogTitle: 'Add documents',
        type: fp.FileType.custom,
        allowedExtensions: [
          'pdf',
          'epub',
          'docx',
          'docm',
          'xlsx',
          'xlsm',
          'pptx',
          'pptm',
          'txt',
          'text',
          'md',
          'cbz',
          'mobi',
          'prc',
          'azw3',
          'kfx',
          'fb2',
          'rtf',
          'doc',
          'odt',
        ],
      );
    }
    if (!mounted || paths.isEmpty) return;
    late final String? message;
    try {
      message = await ref.read(importRunnerProvider.notifier).run(paths);
    } finally {
      // The picker caches picked files in its own temp dir; the library keeps
      // its own copies, so those temporary duplicates are pure waste.
      try {
        await fp.FilePicker.clearTemporaryFiles();
      } on Object {
        // Best effort: some platforms/versions don't implement this.
      }
    }
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
    // Auto-sync new imports (silently; failure shows a snackbar).
    unawaited(_autoSync());
  }

  /// Battery sync hook: persist the define-provided account into secure
  /// storage before the boot auto-sync kicks in.
  Future<void> _batterySyncSetup() async {
    await ref
        .read(webdavAccountStoreProvider.notifier)
        .save(
          WebdavAccount(
            url: batterySyncUrl,
            user: 'docview',
            password: 'docview',
          ),
        );
  }

  /// Boot auto-sync: runs silently when an account exists; failures surface
  /// as a snackbar, successes stay quiet.
  Future<void> _autoSync({bool announce = false}) async {
    final account = await ref.read(webdavAccountStoreProvider.future);
    if (account == null || !mounted) return;
    final message = await ref.read(syncRunnerProvider.notifier).run();
    if (!mounted || message == null) return;
    if (announce || message.startsWith('Sync failed')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _syncNow() async {
    final message = await ref.read(syncRunnerProvider.notifier).run();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'Set up WebDAV sync in Settings first.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDoc(Document doc) async {
    // Cloud-only doc (synced metadata but no local file): download first.
    final file = File(doc.storedPath);
    final fileExists = await file.exists();
    final startMessenger = mounted ? ScaffoldMessenger.of(context) : null;
    if (!fileExists) {
      final engine = ref.read(syncEngineProvider);
      if (engine == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              '"${doc.title}" is in your synced library only — set up '
              'WebDAV sync in Settings to download it here.',
            ),
          ),
        );
        return;
      }
      startMessenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Downloading "${doc.title}"…'),
        ),
      );
      try {
        final ok = await engine.downloadBook(doc);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        if (!ok) {
          messenger.showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('"${doc.title}" is not on the sync server.'),
            ),
          );
          return;
        }
        // Re-index the freshly landed body text in the background.
        unawaited(ref.read(textIndexRepositoryProvider).runPending());
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Download failed: $e'),
            ),
          );
        return;
      }
    }
    ref.read(libraryRepositoryProvider).markOpened(doc.id);
    if (!mounted) return;
    context.push('/reader/${doc.id}');
  }

  void _docMenu(Document doc) => showDocOptionsSheet(context, ref, doc);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final prefs = ref.watch(libraryPrefsProvider);
    final prefsN = ref.read(libraryPrefsProvider.notifier);

    final docsAsync = ref.watch(libraryDocsProvider);
    final shelfAsync = ref.watch(continueReadingProvider);
    final importProgress = ref.watch(importRunnerProvider);
    final copyRevision = ref.watch(localCopyRevisionProvider);

    final body = docsAsync.when(
      data: (docs) {
        _scheduleCloudCheck(docs, copyRevision);
        final shelf = shelfAsync.value ?? const <Document>[];

        if (docs.isEmpty && prefs.search.isEmpty) {
          return _EmptyLibrary(onImport: () => _import());
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
                      cloudOnlyIds: _cloudOnly,
                    ),
            ),
            const SliverToBoxAdapter(child: _ChipRow()),
            if (importProgress.running)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Dv.sp20,
                    Dv.sp8,
                    Dv.sp20,
                    0,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: importProgress.fraction,
                      minHeight: 3,
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Dv.sp20,
                Dv.sp8,
                Dv.sp20,
                Dv.sp8,
              ),
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
                      cloudOnly: _cloudOnly,
                    )
                  : _DocList(
                      docs: docs,
                      onOpen: _openDoc,
                      onLongPress: _docMenu,
                      cloudOnly: _cloudOnly,
                    ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
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
        onTools: _showTools,
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(),
        icon: const Icon(Icons.file_open_rounded),
        label: const Text('Add documents'),
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
    required this.onTools,
  });

  final bool searchOpen;
  final TextEditingController searchCtrl;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearch;
  final VoidCallback onImport;
  final VoidCallback onTools;

  @override
  Size get preferredSize => Size.fromHeight(searchOpen ? 116 : 64);

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
                            style: text.headlineMedium?.copyWith(fontSize: 22),
                          )
                        : Text(
                            'DocView',
                            key: const ValueKey('d'),
                            style: text.displaySmall?.copyWith(fontSize: 27),
                          ),
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
                  IconButton(
                    tooltip: 'Tools',
                    onPressed: onTools,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
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
    final collections = ref.watch(collectionsProvider).value ?? const [];
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
          if (collections.isNotEmpty) ...[
            const SizedBox(width: Dv.sp8),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: Dv.sp8),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            for (final col in collections) ...[
              const SizedBox(width: Dv.sp8),
              FilterChip(
                label: Text(col.name),
                selected: prefs.collectionId == col.id,
                onSelected: (_) => n.selectCollection(
                  prefs.collectionId == col.id ? null : col.id,
                ),
              ),
            ],
          ],
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
  ) => FilterChip(
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
          .map(
            (e) => PopupMenuItem<LibrarySort>(
              value: e.key,
              child: Row(
                children: [
                  if (e.key == current)
                    Icon(Icons.check_rounded, size: 18, color: cs.primary)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: Dv.sp8),
                  Text(e.value),
                ],
              ),
            ),
          )
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
    this.cloudOnly = const <int>{},
  });

  final List<Document> docs;
  final void Function(Document) onOpen;
  final void Function(Document) onLongPress;
  final Set<int> cloudOnly;

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
              cloudOnly: cloudOnly.contains(docs[i].id),
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
    this.cloudOnly = const <int>{},
  });

  final List<Document> docs;
  final void Function(Document) onOpen;
  final void Function(Document) onLongPress;
  final Set<int> cloudOnly;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Dv.sp20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
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
                        if (cloudOnly.contains(d.id)) ...[
                          const SizedBox(width: Dv.sp8),
                          Icon(
                            Icons.cloud_download_outlined,
                            size: 18,
                            color: cs.primary,
                          ),
                        ],
                        const SizedBox(width: Dv.sp12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium?.copyWith(fontSize: 15),
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
        }, childCount: docs.length),
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
    child: Icon(
      Icons.menu_book_rounded,
      size: 20,
      color: cs.onPrimaryContainer.withValues(alpha: 0.5),
    ),
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
  /// Only the first screenful staggers; a 200-book library would otherwise
  /// allocate (and tick) controllers that never become visible.
  static const _maxAnimated = 20;
  static const _maxDelayIndex = 20;

  AnimationController? _ctrl;
  bool _runOnce = false;

  @override
  void initState() {
    super.initState();
    if (widget.index < _maxAnimated) {
      _ctrl = AnimationController(vsync: this, duration: Dv.entrance);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = _ctrl;
    if (ctrl == null || _runOnce) return;
    _runOnce = true;
    Future.delayed(Dv.stagger * widget.index.clamp(0, _maxDelayIndex), () {
      if (mounted) ctrl.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) return widget.child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic),
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 0.96,
          end: 1,
        ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic)),
        child: widget.child,
      ),
    );
  }
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

class _ToolsSheet extends StatelessWidget {
  const _ToolsSheet({
    required this.onImportFiles,
    required this.onImportFolder,
    required this.onSyncNow,
  });

  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: Dv.sp12),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Dv.sp24, Dv.sp16, Dv.sp24, 0),
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
          DvSheetTile(
            icon: Icons.sync_rounded,
            label: 'Sync now',
            onTap: onSyncNow,
          ),
          const Divider(),
          DvSheetTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () {
              Navigator.pop(context);
              context.push('/settings');
            },
          ),
          const SizedBox(height: Dv.sp8),
        ],
      ),
    );
  }
}
