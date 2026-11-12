import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../../app/router.dart';
import '../../../core/design/dv.dart';
import '../../../core/design/widgets/empty_state.dart';
import '../../../core/format/doc_format.dart';
import '../../../core/storage/database.dart';
import '../../library/presentation/providers.dart';
import '../domain/viewer_prefs.dart';
import 'reflow_screen.dart';
import 'office_screens.dart';
import 'reader_chrome.dart';

/// Manual (not codegen): drift data-class generics break riverpod_generator.
final docByIdProvider = FutureProvider.family<Document?, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).byId(id),
);

/// ColorFilter applied to rendered page bitmaps only (overlays stay clean).
ColorFilter? _filterFor(ViewerColorMode mode) => switch (mode) {
      ViewerColorMode.normal => null,
      ViewerColorMode.dark => ColorFilter.matrix(const [
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255, //
          0, 0, -1, 0, 255, //
          0, 0, 0, 1, 0,
        ]),
      ViewerColorMode.sepia => ColorFilter.matrix(const [
          0.393, 0.769, 0.189, 0, 0, //
          0.349, 0.686, 0.168, 0, 0, //
          0.272, 0.534, 0.131, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
    };

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.docId, this.debugPath});

  final int docId;

  /// Battery-hook only: open a raw path without a library row (debug builds).
  final String? debugPath;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  final _ctl = pdfrx.PdfViewerController();
  // Created only after the document is ready (onViewerReady): PdfTextSearcher
  // subscribes to controller.document.events in its constructor and crashes
  // when no document is open yet.
  pdfrx.PdfTextSearcher? _searcher;
  bool _batterySearchStarted = false;

  Document? _doc;
  bool get _canSave => widget.debugPath == null && _doc != null;

  int? _initialPage;
  int _pageNumber = 1;
  int _pageCount = 1;
  bool _booting = true;
  bool _searchOpen = false;
  ViewerColorMode _colorMode = ViewerColorMode.normal;

  final _searchCtrl = TextEditingController();
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSave();
    _searcher?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _flushSave();
  }

  Future<void> _load() async {
    if (widget.debugPath != null) {
      _doc = null; // pseudo-doc: viewer runs from raw path, saving disabled
      _booting = false;
      return;
    }
    final repo = ref.read(libraryRepositoryProvider);
    final doc = await repo.byId(widget.docId);
    if (!mounted) return;
    if (doc == null) {
      _doc = null;
      _booting = false;
      return;
    }
    await repo.markOpened(doc.id);
    final pos = await ref.read(readingRepositoryProvider).ensure(doc.id);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _colorMode = pos.colorMode;
      _initialPage = pos.pageNumber;
      _pageNumber = pos.pageNumber;
      _booting = false;
    });
    if (batteryHook && batterySearchTerm.isNotEmpty) {
      // Actual startTextSearch happens in onViewerReady once the searcher
      // exists; opening the bar early still commits the query text.
      setState(() {
        _searchOpen = true;
        _searchCtrl.text = batterySearchTerm;
      });
    }
  }

  void _flushSave() {
    if (!_canSave) return;
    final n = _ctl.pageNumber;
    if (n == null) return;
    _saveDebounce?.cancel();
    ref.read(readingRepositoryProvider).savePage(_doc!.id, n);
  }

  void _scheduleSave() {
    if (!_canSave) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      ref.read(readingRepositoryProvider).savePage(_doc!.id, _pageNumber);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_booting) {
      return _ReaderScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: cs.primary),
              const SizedBox(height: Dv.sp16),
              Text('Opening…', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    // Debug path: run the viewer straight from the file, no library row.
    if (widget.debugPath != null) {
      return _buildViewer(
        title: 'Debug PDF',
        cs: cs,
        path: widget.debugPath!,
      );
    }

    if (_doc == null) {
      return _ReaderScaffold(
        child: EmptyState(
          icon: Icons.search_off_rounded,
          heading: 'Not found',
          body: 'This document is no longer in your library.',
          actionLabel: 'Back',
          onAction: () => context.pop(),
        ),
      );
    }

    final doc = _doc!;
    if (doc.format != DocFormat.pdf) {
      if (reflowFormats.contains(doc.format)) {
        return ReflowScreen(doc: doc);
      }
      switch (doc.format) {
        case DocFormat.docx:
          return DocxScreen(doc: doc);
        case DocFormat.xlsx:
          return XlsxScreen(doc: doc);
        case DocFormat.pptx:
          return PptxScreen(doc: doc);
        case DocFormat.odt:
        case DocFormat.rtf:
          return TextDocScreen(doc: doc);
        case DocFormat.doc:
        case DocFormat.ppt:
          return _ReaderScaffold(
            child: EmptyState(
              icon: Icons.auto_stories_rounded,
              heading: '"${doc.title}"',
              body: 'Legacy Word/PowerPoint files aren\'t supported in this '
                  'build. Open the file once in Word, PowerPoint, or '
                  'LibreOffice and re-save it as .docx/.pptx to read it here.',
              actionLabel: 'Back',
              onAction: () => context.pop(),
            ),
          );
        case _:
          break;
      }
      return _ReaderScaffold(
        child: EmptyState(
          icon: Icons.auto_stories_rounded,
          heading: '"${doc.title}"',
          body: 'This format is not supported yet.',
          actionLabel: 'Back',
          onAction: () => context.pop(),
        ),
      );
    }

    return _buildViewer(title: doc.title, cs: cs, path: doc.storedPath);
  }

  Widget _buildViewer({
    required String title,
    required ColorScheme cs,
    required String path,
  }) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          if (_searchOpen && _searcher != null)
            AnimatedBuilder(
              animation: _searcher!,
              builder: (context, _) {
                final matches = _searcher!.matches;
                final idx = _searcher!.currentIndex;
                final countText = matches.isEmpty
                    ? ''
                    : '${(idx ?? 0) + 1}/${matches.length}';
                return ReaderSearchBar(
                  controller: _searchCtrl,
                  busy: _searcher!.isSearching && matches.isEmpty,
                  countText: countText,
                  onQuery: (v) {
                    if (v.trim().isEmpty) {
                      _searcher!.resetTextSearch();
                      return;
                    }
                    _searcher!.startTextSearch(v, caseInsensitive: true);
                  },
                  onPrev: () => _searcher!.goToPrevMatch(),
                  onNext: () => _searcher!.goToNextMatch(),
                  onClose: () {
                    setState(() => _searchOpen = false);
                    _searcher!.resetTextSearch();
                  },
                );
              },
            ),
          Expanded(
            child: pdfrx.PdfViewer.file(
              path,
              controller: _ctl,
              initialPageNumber: _initialPage ?? 1,
              params: pdfrx.PdfViewerParams(
                backgroundColor: _colorMode == ViewerColorMode.dark
                    ? const Color(0xFF211D19)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.75),
                pageImageColorFilter: _filterFor(_colorMode),
                pagePaintCallbacks: [?_searcher?.pageTextMatchPaintCallback],
                matchTextColor: Colors.white.withValues(alpha: 0.6),
                activeMatchTextColor: Colors.white,
                onPageChanged: (number) {
                  if (number == null || number == _pageNumber) return;
                  setState(() {
                    _pageNumber = number;
                  });
                  _scheduleSave();
                },
                onViewerReady: (document, _) {
                  setState(() {
                    _pageCount = document.pages.length;
                    _searcher ??= pdfrx.PdfTextSearcher(_ctl);
                  });
                  if (batteryHook &&
                      batterySearchTerm.isNotEmpty &&
                      !_batterySearchStarted) {
                    _batterySearchStarted = true;
                    _searchCtrl.text = batterySearchTerm;
                    _searcher!
                        .startTextSearch(batterySearchTerm, caseInsensitive: true);
                  }
                },
              ),
            ),
          ),
          _BottomBar(
            current: _pageNumber,
            total: _pageCount,
            cs: cs,
            onPage: (v) => _ctl.goToPage(pageNumber: v),
            colorMode: _colorMode,
            onColorCycle: _cycleColorMode,
            onSearchOpen: () => setState(() => _searchOpen = true),
            onOutline: _showOutline,
          ),
        ],
      ),
    );
  }

  Future<void> _cycleColorMode() async {
    final next = ViewerColorMode
        .values[(_colorMode.index + 1) % ViewerColorMode.values.length];
    setState(() => _colorMode = next);
    if (_canSave) {
      await ref.read(readingRepositoryProvider).savePrefs(
            _doc!.id,
            colorMode: next,
          );
    }
  }

  Future<void> _showOutline() async {
    List<pdfrx.PdfOutlineNode>? nodes;
    try {
      await _ctl.useDocument((doc) async {
        nodes = await doc.loadOutline();
      });
    } catch (_) {}
    if (!mounted) return;
    if (nodes == null || nodes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This document has no outline'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        ),
      );
      return;
    }

    // Flatten (indent = depth) for a plain scrolling list.
    final entries = <_OutlineEntry>[];
    void walk(Iterable<pdfrx.PdfOutlineNode> list, int depth) {
      for (final n in list) {
        entries.add(_OutlineEntry(node: n, depth: depth));
        walk(n.children, depth + 1);
      }
    }

    walk(nodes!, 0);

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => ListView.builder(
          controller: scrollCtrl,
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final e = entries[i];
            final dest = e.node.dest;
            return ListTile(
              contentPadding:
                  EdgeInsets.only(left: Dv.sp20 + (e.depth * Dv.sp16)),
              title: Text(e.node.title, maxLines: 2),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (dest != null) {
                  _ctl.goToPage(pageNumber: dest.pageNumber);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _OutlineEntry {
  const _OutlineEntry({required this.node, required this.depth});
  final pdfrx.PdfOutlineNode node;
  final int depth;
}

// --- scaffold / search / bottom bar -----------------------------------------

class _ReaderScaffold extends StatelessWidget {
  const _ReaderScaffold({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(backgroundColor: cs.surface),
      body: child,
    );
  }
}


class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.current,
    required this.total,
    required this.cs,
    required this.onPage,
    required this.colorMode,
    required this.onColorCycle,
    required this.onSearchOpen,
    required this.onOutline,
  });

  final int current;
  final int total;
  final ColorScheme cs;
  final ValueChanged<int> onPage;
  final ViewerColorMode colorMode;
  final VoidCallback onColorCycle;
  final VoidCallback onSearchOpen;
  final VoidCallback onOutline;

  static const _icons = {
    ViewerColorMode.normal: Icons.circle_outlined,
    ViewerColorMode.sepia: Icons.circle,
    ViewerColorMode.dark: Icons.nights_stay_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Outline',
              onPressed: onOutline,
              icon: const Icon(Icons.format_list_bulleted_rounded),
            ),
            IconButton(
              tooltip: 'Search',
              onPressed: onSearchOpen,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: 'Color: $colorMode',
              onPressed: onColorCycle,
              icon: Icon(_icons[colorMode] ?? Icons.circle_outlined),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: current.clamp(1, total < 1 ? 1 : total).toDouble(),
                  max: (total < 1 ? 1 : total).toDouble(),
                  divisions: total < 2 ? null : total - 1,
                  onChanged: (v) => onPage(v.round().clamp(1, total)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: Dv.sp12),
              child: Text(
                '$current / $total',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
