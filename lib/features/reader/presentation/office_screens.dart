import 'dart:async';
import 'dart:io';

import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:excel_plus/excel_plus.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/design/dv.dart';
import '../../../core/format/doc_format.dart';
import '../../../core/storage/database.dart';
import '../data/odt_text.dart';
import '../data/pptx_text.dart';
import '../data/rtf_text.dart';
import '../data/text_search.dart';
import '../domain/viewer_prefs.dart';
import '../../library/presentation/providers.dart';

/// Paper colors per reading mode, shared by the office readers.
Color officeSurface(ColorScheme cs, ViewerColorMode mode) => switch (mode) {
      ViewerColorMode.normal => cs.surface,
      ViewerColorMode.sepia => const Color(0xFFF4EAD5),
      ViewerColorMode.dark => const Color(0xFF211D19),
    };

/// Text colors that keep contrast on top of [officeSurface].
Color officeText(ColorScheme cs, ViewerColorMode mode) => switch (mode) {
      ViewerColorMode.normal => cs.onSurface,
      ViewerColorMode.sepia => const Color(0xFF3F3225),
      ViewerColorMode.dark => const Color(0xFFEDE7DE),
    };

/// Base state for the office readers: restores color mode / scroll position,
/// exposes debounced saveProgress and flushes on lifecycle events.
abstract class OfficeReaderState<W extends ConsumerStatefulWidget>
    extends ConsumerState<W> with WidgetsBindingObserver {
  Timer? _saveDebounce;
  ViewerColorMode _colorMode = ViewerColorMode.normal;
  bool _booting = true;
  String? _error;

  ViewerColorMode get colorMode => _colorMode;
  bool get booting => _booting;
  String? get error => _error;

  Document? get doc;
  bool get canSave => doc != null;

  /// Decode the document; throwing leaves the error screen up.
  Future<void> loadDocument();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSave();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _flushSave();
  }

  Future<void> _restore() async {
    try {
      await loadDocument();
      if (canSave) {
        final pos = await ref.read(readingRepositoryProvider).ensure(doc!.id);
        _colorMode = pos.colorMode;
        if (pos.progress != null) {
          onProgressRestored(pos.progress!, pos.location);
        }
      }
    } on Object catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _booting = false);
        maybeAutoSearch();
      }
    }
  }

  /// Subclasses override to apply a restored scroll fraction / location.
  void onProgressRestored(double fraction, String? location) {}

  void reportError(Object e) {
    if (mounted) setState(() => _error = e.toString());
  }

  void cycleColorMode() {
    final next = ViewerColorMode
        .values[(_colorMode.index + 1) % ViewerColorMode.values.length];
    setState(() => _colorMode = next);
    if (canSave) {
      unawaited(ref
          .read(readingRepositoryProvider)
          .savePrefs(doc!.id, colorMode: next));
    }
  }

  void scheduleProgressSave(double fraction, String? location) {
    if (!canSave) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      ref
          .read(readingRepositoryProvider)
          .saveProgress(doc!.id, fraction, location);
    });
  }

  void _flushSave() {
    _saveDebounce?.cancel();
    persistProgress();
  }

  /// Subclasses provide the current fraction/location for the final write.
  void persistProgress() {}

  /// Fraction of a scrollable's extent from a controller (0 when unloaded).
  double scrollFraction(ScrollController controller) {
    if (!controller.hasClients) return 0;
    final max = controller.position.maxScrollExtent;
    return (max > 0 ? controller.offset / max : 0).clamp(0, 1).toDouble();
  }

  // --- in-document search ----------------------------------------------------
  // Formats with their own search UI (docx) return null from searchableLines
  // and get no search icon; the rest expose one searchable line per unit
  // (paragraph / row / slide) and jump via jumpToSearchHit.

  /// Searchable lines, or null when this screen has its own search UI.
  List<String>? searchableLines() => null;

  /// Called when a result of [searchableLines] is picked in the sheet.
  void jumpToSearchHit(int lineIndex) {}

  void _openSearchSheet({bool batteryAuto = false}) {
    final lines = searchableLines();
    if (lines == null || lines.isEmpty) return;
    if (!mounted) return;
    unawaited(showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
      ),
      builder: (sheetCtx) => _OfficeSearchSheet(
        lines: lines,
        initialQuery: batteryAuto ? batterySearchTerm : null,
        onJump: (idx) {
          Navigator.maybePop(sheetCtx);
          jumpToSearchHit(idx);
        },
      ),
    ));
  }

  Widget buildLoading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening…'),
          ],
        ),
      );

  Widget buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(height: 12),
            SizedBox(
              width: 300,
              child: Text(
                _error ?? 'Could not open this document',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      );

  Widget buildOfficeScaffold({
    required Widget body,
    Widget? bottomBar,
  }) {
    final theme = Theme.of(context);
    final bg = officeSurface(theme.colorScheme, _colorMode);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          doc?.title ?? 'Document',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!_booting && _error == null && searchableLines() != null)
            IconButton(
              tooltip: 'Search',
              onPressed: () => _openSearchSheet(),
              icon: const Icon(Icons.search_rounded),
            ),
          IconButton(
            tooltip: 'Color: $_colorMode',
            onPressed: cycleColorMode,
            icon: Icon(switch (_colorMode) {
              ViewerColorMode.normal => Icons.contrast_rounded,
              ViewerColorMode.sepia => Icons.circle,
              ViewerColorMode.dark => Icons.nights_stay_rounded,
            }),
          ),
        ],
      ),
      body: _booting
          ? buildLoading()
          : (_error != null ? buildError() : body),
      bottomNavigationBar: bottomBar,
    );
  }

  void maybeAutoSearch() {
    if (!batteryHook || batterySearchTerm.isEmpty) return;
    if (searchableLines() == null) return;
    if (searchableLines()!.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSearchSheet(batteryAuto: true);
    });
  }
}

// --- DOCX --------------------------------------------------------------------

class DocxScreen extends ConsumerStatefulWidget {
  const DocxScreen({super.key, required this.doc});

  final Document doc;

  @override
  ConsumerState<DocxScreen> createState() => _DocxScreenState();
}

class _DocxScreenState extends OfficeReaderState<DocxScreen> {
  @override
  Document? get doc => widget.doc;

  @override
  Future<void> loadDocument() async {
    final file = File(widget.doc.storedPath);
    if (!file.existsSync()) {
      throw StateError('File is missing from storage');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (booting || error != null) {
      return buildOfficeScaffold(body: const SizedBox.shrink());
    }
    final cs = Theme.of(context).colorScheme;
    final bg = officeSurface(cs, _colorMode);
    // Dark preset carries light-on-dark text styles; others use light text.
    final theme = switch (_colorMode) {
      ViewerColorMode.dark => DocxViewTheme.dark(),
      _ => DocxViewTheme.light(),
    };
    final config = DocxViewConfig(
      enableSearch: true,
      enableZoom: true,
      enableSelection: true,
      theme: theme,
      backgroundColor: bg,
    );

    return buildOfficeScaffold(
      body: DocxViewWithSearch(
        file: File(widget.doc.storedPath),
        config: config,
      ),
    );
  }
}

// --- XLSX --------------------------------------------------------------------

class XlsxScreen extends ConsumerStatefulWidget {
  const XlsxScreen({super.key, required this.doc});

  final Document doc;

  @override
  ConsumerState<XlsxScreen> createState() => _XlsxScreenState();
}

class _XlsxScreenState extends OfficeReaderState<XlsxScreen> {
  List<String> _sheetNames = const [];
  Map<String, List<List<String>>> _sheets = const {};
  String _current = '';
  final _scroll = ScrollController();
  static const _rowCap = 3000;

  @override
  Document? get doc => widget.doc;

  @override
  Future<void> loadDocument() async {
    final bytes = await File(widget.doc.storedPath).readAsBytes();
    final excel = await Excel.decodeBytesAsync(bytes);
    final names = excel.tables.keys.toList();
    if (names.isEmpty) throw StateError('Workbook has no sheets');

    final sheets = <String, List<List<String>>>{};
    for (final name in names) {
      final rows = <List<String>>[];
      // Cap giant sheets; the reader view is a quick look, not an editor.
      for (final row in excel[name].rows.take(_rowCap)) {
        rows.add([for (final cell in row) cell?.displayText ?? '']);
      }
      _dropEmptyTrailing(rows);
      if (rows.isNotEmpty) sheets[name] = rows;
    }
    _sheetNames = [for (final n in names) if (sheets.containsKey(n)) n];
    if (_sheetNames.isEmpty) throw StateError('All sheets are empty');
    _sheets = sheets;
    _current = _sheetNames.first;
  }

  static void _dropEmptyTrailing(List<List<String>> rows) {
    while (rows.isNotEmpty && rows.last.every((c) => c.isEmpty)) {
      rows.removeLast();
    }
  }

  @override
  void onProgressRestored(double fraction, String? location) {
    if (location != null && _sheetNames.contains(location)) {
      _current = location;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) _scroll.jumpTo(fraction.clamp(0, 1) * max);
    });
  }

  @override
  void persistProgress() {
    if (!_scroll.hasClients) return;
    scheduleProgressSave(scrollFraction(_scroll), _current);
  }

  @override
  List<String>? searchableLines() =>
      [for (final r in _sheets[_current] ?? const <List<String>>[]) r.join(' · ')];

  @override
  void jumpToSearchHit(int lineIndex) {
    final rows = _sheets[_current] ?? const <List<String>>[];
    if (rows.isEmpty || lineIndex >= rows.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(((lineIndex / rows.length).clamp(0, 1) * max));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (booting || error != null) {
      return buildOfficeScaffold(body: const SizedBox.shrink());
    }
    final cs = Theme.of(context).colorScheme;
    final rows = _sheets[_current] ?? const <List<String>>[];
    final columnCount =
        rows.fold<int>(0, (n, row) => n < row.length ? row.length : n);
    final header = rows.isEmpty ? const <String>[] : rows.first;
    final dataRows =
        rows.isEmpty ? const <List<String>>[] : rows.sublist(1);

    TextStyle cellStyle(bool headerRow) => TextStyle(
          fontSize: 13,
          fontWeight: headerRow ? FontWeight.w600 : FontWeight.normal,
          color: officeText(cs, _colorMode),
        );

    TableRow tableRow(List<String> cells, {bool headerRow = false}) {
      final style = cellStyle(headerRow);
      return TableRow(
        decoration: headerRow
            ? BoxDecoration(
                color:
                    cs.surfaceContainerHighest.withValues(alpha: 0.55),
              )
            : null,
        children: [
          for (var c = 0; c < columnCount; c++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                c < cells.length ? cells[c] : '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
        ],
      );
    }

    Widget table = Table(
      columnWidths: {
        for (var c = 0; c < columnCount; c++) c: const IntrinsicColumnWidth(),
      },
      border: TableBorder.all(
        color: cs.outlineVariant.withValues(alpha: 0.45),
        width: 0.6,
      ),
      children: [
        if (header.isNotEmpty) tableRow(header, headerRow: true),
        for (final row in dataRows) tableRow(row),
      ],
    );

    Widget body = Column(
      children: [
        if (_sheetNames.length > 1)
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _sheetNames.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final name = _sheetNames[i];
                return ChoiceChip(
                  label: Text(name),
                  selected: name == _current,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _current = name),
                );
              },
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: table,
              ),
            ),
          ),
        ),
        if (dataRows.length >= _rowCap - 1)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Showing first $_rowCap rows — truncated',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );

    // Debounced-ish progress capture on scroll settles.
    body = NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        persistProgress();
        return false;
      },
      child: body,
    );

    return buildOfficeScaffold(body: body);
  }
}

// --- PPTX --------------------------------------------------------------------

class PptxScreen extends ConsumerStatefulWidget {
  const PptxScreen({super.key, required this.doc});

  final Document doc;

  @override
  ConsumerState<PptxScreen> createState() => _PptxScreenState();
}

class _PptxScreenState extends OfficeReaderState<PptxScreen> {
  List<PptxSlide> _slides = const [];

  @override
  Document? get doc => widget.doc;

  @override
  Future<void> loadDocument() async {
    final bytes = await File(widget.doc.storedPath).readAsBytes();
    _slides = extractPptxSlides(bytes);
  }

  @override
  List<String>? searchableLines() => [
        for (final s in _slides)
          s.title.isEmpty
              ? s.body.join(' — ')
              : '${s.title} — ${s.body.join(' — ')}',
      ];

  @override
  void jumpToSearchHit(int lineIndex) {
    if (lineIndex >= _slides.length) return;
    _openSlide(context, _slides[lineIndex]);
  }

  @override
  Widget build(BuildContext context) {
    if (booting || error != null) {
      return buildOfficeScaffold(body: const SizedBox.shrink());
    }
    return buildOfficeScaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _slides.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final slide = _slides[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${slide.number}')),
              title: Text(
                slide.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: slide.body.isEmpty
                  ? null
                  : Text(
                      slide.body.join('  ·  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => _openSlide(context, slide),
            ),
          );
        },
      ),
    );
  }

  void _openSlide(BuildContext context, PptxSlide slide) {
    final cs = Theme.of(context).colorScheme;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: officeSurface(cs, colorMode),
        appBar: AppBar(
          title: Text('Slide ${slide.number}'),
          backgroundColor: officeSurface(cs, colorMode),
          surfaceTintColor: Colors.transparent,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in slide.lines) ...[
                SelectableText(
                  line,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: officeText(cs, colorMode),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    ));
  }
}

// --- ODT / RTF ---------------------------------------------------------------

class TextDocScreen extends ConsumerStatefulWidget {
  const TextDocScreen({super.key, required this.doc});

  final Document doc;

  @override
  ConsumerState<TextDocScreen> createState() => _TextDocScreenState();
}

class _TextDocScreenState extends OfficeReaderState<TextDocScreen> {
  List<OdtParagraph> _paragraphs = const [];
  final _scroll = ScrollController();

  @override
  Document? get doc => widget.doc;

  @override
  Future<void> loadDocument() async {
    final bytes = await File(widget.doc.storedPath).readAsBytes();
    _paragraphs = switch (widget.doc.format) {
      DocFormat.odt => extractOdtParagraphs(bytes),
      DocFormat.rtf => [
          // RTF bytes map 1:1 to latin1 chars; \'hh + \uN handle the rest.
          for (final line in extractRtfText(String.fromCharCodes(bytes))
              .split('\n'))
            if (line.isNotEmpty) OdtParagraph(text: line, isHeading: false),
        ],
      _ => throw StateError('Unsupported format for text view'),
    };
    if (_paragraphs.isEmpty) throw StateError('No text found');
  }

  @override
  void onProgressRestored(double fraction, String? location) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) _scroll.jumpTo(fraction.clamp(0, 1) * max);
    });
  }

  @override
  void persistProgress() {
    if (!_scroll.hasClients) return;
    scheduleProgressSave(scrollFraction(_scroll), null);
  }

  @override
  List<String>? searchableLines() => [for (final par in _paragraphs) par.text];

  @override
  void jumpToSearchHit(int lineIndex) {
    if (lineIndex >= _paragraphs.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(
        ((lineIndex / _paragraphs.length).clamp(0, 1) * max),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (booting || error != null) {
      return buildOfficeScaffold(body: const SizedBox.shrink());
    }
    final cs = Theme.of(context).colorScheme;
    final textColor = officeText(cs, _colorMode);

    return buildOfficeScaffold(
      body: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          persistProgress();
          return false;
        },
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _paragraphs.length,
          itemBuilder: (_, i) {
            final par = _paragraphs[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SelectableText(
                par.text,
                style: TextStyle(
                  fontSize: par.isHeading ? 20 : 16,
                  height: 1.55,
                  fontWeight: par.isHeading ? FontWeight.w700 : FontWeight.normal,
                  color: textColor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- office search sheet ------------------------------------------------------

class _OfficeSearchSheet extends StatefulWidget {
  const _OfficeSearchSheet({
    required this.lines,
    required this.onJump,
    this.initialQuery,
  });

  final List<String> lines;
  final void Function(int lineIndex) onJump;
  final String? initialQuery;

  @override
  State<_OfficeSearchSheet> createState() => _OfficeSearchSheetState();
}

class _OfficeSearchSheetState extends State<_OfficeSearchSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery ?? '');
  List<TextHit> _hits = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _recompute();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _recompute() {
    setState(() => _hits = findTextHits(widget.lines, _ctrl.text));
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), _recompute);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search in document',
              isDense: true,
              suffixIcon: _hits.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        child: Text('${_hits.length}',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Dv.rLg),
              ),
            ),
            onChanged: _onQuery,
            onSubmitted: (_) => _recompute(),
          ),
        ),
        Expanded(
          child: _hits.isEmpty && _ctrl.text.trim().isEmpty
              ? Center(
                  child: Text(
                    'Type to search ${widget.lines.length} items',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : _hits.isEmpty
                  ? Center(
                      child: Text(
                        'No matches',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _hits.length,
                      itemBuilder: (_, i) {
                        final hit = _hits[i];
                        return ListTile(
                          dense: true,
                          title: RichText(
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: DefaultTextStyle.of(context)
                                  .style
                                  .copyWith(fontSize: 14),
                              children: [
                                TextSpan(text: hit.pre),
                                TextSpan(
                                  text: hit.hit,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                                ),
                                TextSpan(text: hit.post),
                              ],
                            ),
                          ),
                          onTap: () => widget.onJump(hit.index),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Back'),
            ),
          ),
        ),
      ],
    );
  }
}
