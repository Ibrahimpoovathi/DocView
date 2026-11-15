// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/router.dart';
import '../../../core/design/dv.dart';
import '../../../core/paths/app_paths.dart';
import '../../../core/design/widgets/empty_state.dart';
import '../../../core/format/doc_format.dart';
import '../../../core/storage/database.dart';
import '../data/book_server.dart';
import '../data/foliate_assets.dart';
import '../data/reading_repository.dart';
import '../domain/annotations.dart';
import '../../library/presentation/providers.dart';
import '../../dictionary/presentation/dictionary_sheet.dart';
import '../../sync/presentation/sync_providers.dart';
import 'annotation_palette.dart';
import 'annotation_sheets.dart';
import 'annotations_list.dart';
import 'reader_chrome.dart';
import '../domain/viewer_prefs.dart';

/// Formats rendered by the embedded foliate-js engine over localhost.
const reflowFormats = {
  DocFormat.epub,
  DocFormat.mobi,
  DocFormat.azw3,
  DocFormat.fb2,
  DocFormat.txt,
  DocFormat.cbz,
};

class ReflowScreen extends ConsumerStatefulWidget {
  const ReflowScreen({
    super.key,
    this.doc,
    this.debugPath,
    this.debugTitle = 'Debug format',
  });

  final Document? doc;

  /// Battery/debug: serve a raw path bypassing library rows.
  final String? debugPath;
  final String debugTitle;

  @override
  ConsumerState<ReflowScreen> createState() => _ReflowScreenState();
}

class _ReflowScreenState extends ConsumerState<ReflowScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _web;

  Future<WebUri>? _bookUrlFuture;
  double _fraction = 0;
  String? _location;
  int? _permilleViewed;
  bool _booting = true;
  String? _error;

  Timer? _saveDebounce;

  /// Reading repo captured in initState — dispose() flushes progress and
  /// must not call ref.read (unmounted-ref crash during the audit battery).
  late final ReadingRepository _readingRepo;
  ViewerColorMode _colorMode = ViewerColorMode.normal;

  // In-document search (foliate view.search behind the WebView bridge).
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _searching = false;
  int _searchCount = 0;
  List<ReflowHit> _hits = const [];
  int _hitIdx = 0;
  bool _searchFailed = false;

  // Annotations: DB rows for this document (lookup by uuid on tap) plus the
  // selection awaiting a highlight/note action.
  List<Annotation> _annotations = const [];
  ({String text, String cfi})? _selAction;

  Document? get _doc => widget.doc;
  bool get _canSave => widget.doc != null;

  String _title() => _doc?.title ?? widget.debugTitle;

  @override
  void initState() {
    super.initState();
    // Captured eagerly: dispose() flushes progress and must not touch ref.
    _readingRepo = ref.read(readingRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _prepare();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _flushSave();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSave();
    _searchDebounce?.cancel();
    _dictDebounce?.cancel();
    _searchCtrl.dispose();
    unawaited(BookServer.stop());
    super.dispose();
  }

  Future<void> _flushSave() async {
    if (!_canSave) return;
    _saveDebounce?.cancel();
    await _readingRepo.saveProgress(_doc!.id, _fraction, _location);
  }

  Future<void> _prepare() async {
    // Restore color mode + last position before building the webview URL.
    if (widget.doc != null) {
      final pos =
          await ref.read(readingRepositoryProvider).ensure(widget.doc!.id);
      _annotations =
          await ref.read(annotationsRepositoryProvider).listForDoc(widget.doc!.id);
      _ensureBookUrl();
      if (!mounted) return;
      setState(() {
        _colorMode = pos.colorMode;
        if (pos.progress != null) _fraction = pos.progress!;
        _location = pos.location;
        _permilleViewed = (pos.progress ?? 0) > 0
            ? (pos.progress! * 1000).round()
            : null;
      });
    }
  }

  Future<WebUri> _ensureBookUrl() =>
      _bookUrlFuture ??= _bookUrl().catchError((Object e) {
        // ignore: invalid_use_of_protected_member
        setState(() => _error = e.toString());
        throw e;
      });

  Future<WebUri> _bookUrl() async {
    await installFoliateAssets();
    final port = await BookServer.ensureRunning();
    final t = BookServer.token;
    final base = 'http://127.0.0.1:$port';

    final String sourceUrl;
    if (widget.debugPath != null) {
      sourceUrl =
          '$base/files/${p.split(widget.debugPath!).last}?t=$t';
    } else {
      final rel = p
          .relative(widget.doc!.storedPath,
              from: AppPaths.booksDir.path)
          .replaceAll(r'\', '/');
      final enc = rel.split('/').map(Uri.encodeComponent).join('/');
      sourceUrl = _doc!.format == DocFormat.txt
          ? '$base/txt/$enc?t=$t'
          : _doc!.format == DocFormat.fb2
              ? '$base/fb2/$enc?t=$t'
              : '$base/files/$enc?t=$t';
    }

    final q = StringBuffer(
        '$base/foliate/docview.html?src=${Uri.encodeComponent(sourceUrl)}'
        '&t=$t'
        '&color=${_colorMode.name}');
    if (_fraction > 0.001) {
      q.write('&frac=${_fraction.toStringAsFixed(4)}');
    }
    if (_location != null && _location!.isNotEmpty) {
      q.write('&loc=${Uri.encodeComponent(_location!)}');
    }
    return WebUri(q.toString());
  }

  void _scheduleSave() {
    if (!_canSave) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      // Timer callbacks can fire after unmount; _readingRepo is field-safe.
      _readingRepo.saveProgress(_doc!.id, _fraction, _location);
    });
  }

  Future<void> _cycleColorMode() async {
    final next = ViewerColorMode
        .values[(_colorMode.index + 1) % ViewerColorMode.values.length];
    setState(() => _colorMode = next);
    // Re-colour in place: a rebuilt WebView loses reading position and
    // re-parses the whole book.
    unawaited(_web?.evaluateJavascript(
          source: "window.docviewSetColor('${next.name}')",
        ) ??
        Future.value());
    if (_canSave) {
      await ref
          .read(readingRepositoryProvider)
          .savePrefs(_doc!.id, colorMode: next);
    }
  }

  Future<void> _showOutline() async {
    final web = _web;
    if (web == null) return;
    final dynamic toc =
        await web.evaluateJavascript(source: 'window.docviewToc()');
    if (!mounted) return;
    if (toc == null || (toc as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No outline'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      ));
      return;
    }
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
          itemCount: toc.length,
          itemBuilder: (_, i) {
            final entry = toc[i] as Map;
            final depth = (entry['depth'] as num?)?.toInt() ?? 0;
            final href = entry['href'] as String?;
            return ListTile(
              contentPadding:
                  EdgeInsets.only(left: Dv.sp20 + (depth * Dv.sp16)),
              title: Text(
                entry['label']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (href != null) {
                  _web?.evaluateJavascript(
                      source: 'window.docviewGoTo(${_jsonStr(href)})');
                }
              },
            );
          },
        ),
      ),
    );
  }

  static String _jsonStr(String s) => "'${s.replaceAll("'", r"\'")}'";

  // --- annotations -------------------------------------------------------------

  /// Battery-only: simulate a multi-word selection (JS), create a
  /// highlight + note + bookmark, optionally sync, then open the
  /// annotations list for the screenshot.
  Future<void> _batteryNoteFlow() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await _web?.evaluateJavascript(source: 'window.docviewBatterySelect()');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    if (_selAction != null) {
      await _createReflowHighlight('yellow');
    }
    final doc = _doc;
    final cfi = _location;
    if (doc != null && cfi != null) {
      await ref.read(annotationsRepositoryProvider).create(
            doc.id,
            kind: AnnotationKind.note,
            anchor: AnnotationAnchor(cfi: cfi),
            excerpt: 'Battery note excerpt',
            note: 'Battery note body',
          );
      await _toggleReflowBookmark();
    }
    if (batterySyncUrl.isNotEmpty) {
      // Wait for a sync run that actually executes (the boot auto-sync may
      // still hold the runner; a completed run is a full pull+push, so the
      // annotations list below reflects the merged state).
      for (var i = 0; i < 5; i++) {
        final message = await ref.read(syncRunnerProvider.notifier).run();
        if (message != null) break;
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    if (!mounted || doc == null) return;
    await showAnnotationsList(context, ref, doc, onJump: (_) {});
  }

  /// Pushes DB highlights into the foliate overlay layer (once per open).
  Future<void> _seedAnnotations() async {
    if (!_canSave) return;
    final web = _web;
    if (web == null) return;
    final rows = <Map<String, Object?>>[
      for (final a in _annotations)
        if (a.kind == AnnotationKind.highlight)
          if (tryParseAnchor(a.anchor)?.cfi case final String cfi)
            {'value': cfi, 'color': a.color ?? 'yellow', 'uuid': a.uuid},
    ];
    if (rows.isEmpty) return;
    await web.evaluateJavascript(
        source: 'window.docviewSetAnnotations(${jsonEncode(rows)})');
  }

  Future<void> _pushAddAnnotation({
    required String cfi,
    required String uuid,
    required String color,
  }) =>
      _web?.evaluateJavascript(source:
          'window.docviewAddAnnotation(${jsonEncode({
            'value': cfi,
            'color': color,
            'uuid': uuid,
          })})') ??
      Future.value();

  Future<void> _pushUpdateAnnotation({
    required String cfi,
    required String uuid,
    required String color,
  }) =>
      _web?.evaluateJavascript(source:
          'window.docviewUpdateAnnotation(${jsonEncode({
            'value': cfi,
            'color': color,
            'uuid': uuid,
          })})') ??
      Future.value();

  Future<void> _pushRemoveAnnotation({
    required String cfi,
    required String uuid,
  }) =>
      _web?.evaluateJavascript(source:
          'window.docviewRemoveAnnotation(${jsonEncode({
            'value': cfi,
            'uuid': uuid,
          })})') ??
      Future.value();

  void _dismissSelAction() {
    if (!mounted) return;
    setState(() => _selAction = null);
    _web?.evaluateJavascript(source: 'window.docviewClearSelection()');
  }

  Future<void> _createReflowHighlight(String colorKey) async {
    final sel = _selAction;
    final doc = _doc;
    if (sel == null || doc == null) return;
    final ann = await ref.read(annotationsRepositoryProvider).create(
          doc.id,
          kind: AnnotationKind.highlight,
          anchor: AnnotationAnchor(cfi: sel.cfi),
          excerpt: sel.text,
          color: colorKey,
        );
    if (!mounted) return;
    setState(() => _annotations = [..._annotations, ann]);
    await _pushAddAnnotation(
        cfi: sel.cfi, uuid: ann.uuid, color: colorKey);
    _dismissSelAction();
  }

  Future<void> _createReflowNote() async {
    final sel = _selAction;
    final doc = _doc;
    if (sel == null || doc == null) return;
    final note = await promptNoteText(context);
    if (note == null || note.isEmpty) {
      _dismissSelAction();
      return;
    }
    final ann = await ref.read(annotationsRepositoryProvider).create(
          doc.id,
          kind: AnnotationKind.note,
          anchor: AnnotationAnchor(cfi: sel.cfi),
          excerpt: sel.text,
          note: note,
        );
    if (!mounted) return;
    setState(() => _annotations = [..._annotations, ann]);
    _dismissSelAction();
  }

  bool _hasReflowBookmarkAt(String cfi) => _annotations.any(
        (a) =>
            a.kind == AnnotationKind.bookmark &&
            tryParseAnchor(a.anchor)?.cfi == cfi,
      );

  Future<void> _toggleReflowBookmark() async {
    final doc = _doc;
    final cfi = _location;
    if (doc == null || cfi == null) return;
    final existing = _annotations
        .where((a) => a.kind == AnnotationKind.bookmark)
        .where((a) =>
            tryParseAnchor(a.anchor)?.cfi == cfi)
        .firstOrNull;
    if (existing != null) {
      await ref.read(annotationsRepositoryProvider).softDelete(existing.id);
      if (!mounted) return;
      setState(() {
        _annotations = _annotations.where((a) => a.id != existing.id).toList();
      });
      return;
    }
    final ann = await ref.read(annotationsRepositoryProvider).create(
          doc.id,
          kind: AnnotationKind.bookmark,
          anchor: AnnotationAnchor(cfi: cfi),
          excerpt: 'Location ${(_fraction * 100).round()}%',
        );
    if (!mounted) return;
    setState(() {
      _annotations = [..._annotations, ann];
    });
  }

  Future<void> _openAnnotationEditor(String uuid) async {    Annotation? find() =>
        _annotations.where((a) => a.uuid == uuid).firstOrNull;
    final ann = find();
    if (ann == null || !mounted) return;
    final cfi = tryParseAnchor(ann.anchor)?.cfi;
    await showAnnotationEditor(
      context,
      ref,
      ann,
      onChanged: (color) {
        if (color == null || cfi == null) return;
        _pushUpdateAnnotation(cfi: cfi, uuid: uuid, color: color);
      },
      onDeleted: () {
        if (cfi != null) {
          _pushRemoveAnnotation(cfi: cfi, uuid: uuid);
        }
        if (mounted) {
          setState(() => _annotations = [
                ..._annotations.where((a) => a.uuid != uuid),
              ]);
        }
      },
    );
  }

  // --- dictionary lookup -----------------------------------------------------

  Timer? _dictDebounce;

  Future<void> _openDictionary(String word) async {
    if (!mounted) return;
    await showDictionarySheet(context, ref, word);
  }

  // --- in-document search ----------------------------------------------------

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _searchFailed = false;
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searchOpen = false;
      _searching = false;
      _hits = const [];
      _hitIdx = 0;
      _searchCount = 0;
      _searchFailed = false;
    });
    _searchCtrl.clear();
    _web?.evaluateJavascript(source: 'window.docviewClearSearch()');
  }

  void _onSearchQuery(String raw) {
    final query = raw.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _hits = const [];
        _hitIdx = 0;
        _searchCount = 0;
        _searchFailed = false;
      });
      _web?.evaluateJavascript(source: 'window.docviewClearSearch()');
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _web?.evaluateJavascript(
        source: 'window.docviewSearch(${jsonEncode(_searchCtrl.text.trim())})',
      );
    });
  }

  void _goHit(int delta) {
    if (_hits.isEmpty) return;
    _hitIdx = (_hitIdx + delta) % _hits.length;
    _jumpToHit(_hits[_hitIdx]);
    setState(() {});
  }

  void _jumpToHit(ReflowHit hit) {
    _web?.evaluateJavascript(
      source: 'window.docviewGoTo(${_jsonStr(hit.cfi)})',
    );
  }

  Future<void> _showHits() async {
    if (_hits.isEmpty) {
      if (_searchFailed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Search stopped early — try a shorter term'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('No matches yet'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        ));
      }
      return;
    }
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
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                '${_hits.length} match${_hits.length == 1 ? '' : 'es'}',
                style: Theme.of(sheetCtx).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _hits.length,
                itemBuilder: (_, i) => ListTile(
                  title: _HitExcerpt(hit: _hits[i]),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _jumpToHit(_hits[i]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          _title(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_canSave)
            IconButton(
              icon: const Icon(Icons.format_list_bulleted_rounded),
              tooltip: 'Annotations',
              onPressed: _doc == null
                  ? null
                  : () => showAnnotationsList(
                        context,
                        ref,
                        _doc!,
                        onJump: (ann) {
                          final cfi = tryParseAnchor(ann.anchor)?.cfi;
                          if (cfi != null) {
                            _web?.evaluateJavascript(
                                source:
                                    'window.docviewShowAnnotation(${_jsonStr(cfi)})');
                          }
                        },
                        onUpdateColor: (ann, color) {
                          final cfi = tryParseAnchor(ann.anchor)?.cfi;
                          if (cfi != null && color != null) {
                            _pushUpdateAnnotation(
                                cfi: cfi, uuid: ann.uuid, color: color);
                          }
                        },
                        onDelete: (ann) {
                          final cfi = tryParseAnchor(ann.anchor)?.cfi;
                          if (cfi != null) {
                            _pushRemoveAnnotation(cfi: cfi, uuid: ann.uuid);
                          }
                        },
                      ),
            ),
          if (_canSave && _location != null)
            IconButton(
              icon: Icon(
                _hasReflowBookmarkAt(_location!)
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: _hasReflowBookmarkAt(_location!) ? cs.primary : null,
              ),
              tooltip: _hasReflowBookmarkAt(_location!)
                  ? 'Remove bookmark'
                  : 'Bookmark this location',
              onPressed: _toggleReflowBookmark,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ReaderSearchBar(
                controller: _searchCtrl,
                busy: _searching && _hits.isEmpty,
                countText: _searching
                    ? (_searchCount > 0 ? '$_searchCount…' : '')
                    : _hits.isEmpty
                        ? ''
                        : '${_hitIdx + 1}/${_hits.length}',
                onQuery: _onSearchQuery,
                onPrev: () => _goHit(-1),
                onNext: () => _goHit(1),
                onCountTap: _showHits,
                onClose: _closeSearch,
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FutureBuilder<WebUri>(
                  future: _ensureBookUrl(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done ||
                        snap.data == null) {
                      return _PulseLoader(cs: cs);
                    }
                    if (_error != null) {
                      return EmptyState(
                        icon: Icons.error_outline_rounded,
                        heading: 'Could not open',
                        body: _error!,
                        actionLabel: 'Back',
                        onAction: () => context.pop(),
                      );
                    }
                    return InAppWebView(
                      initialUrlRequest: URLRequest(url: snap.data!),

                      initialSettings: InAppWebViewSettings(
                        transparentBackground: false,
                        supportZoom: true,
                        useHybridComposition: true,
                      ),
                      onRenderProcessGone: (controller, detail) async {
                        // Renderer crash (native WebView bug) used to leave a
                        // blank route; rebuild the webview with a friendly
                        // banner instead.
                        if (!mounted) return;
                        setState(() => _error =
                            'The document viewer crashed while rendering. '
                            'Reopening may help.');
                        _web = null;
                      },
                      onWebViewCreated: (c) {
                        _web = c;
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowProgress',
                          callback: (args) {
                            final payload = args.isNotEmpty
                                ? args.first as Map
                                : const <String, dynamic>{};
                            final f = (payload['fraction'] as num?)?.toDouble();
                            if (f != null && f > 0) {
                              _fraction = f;
                              _permilleViewed = (f * 1000).round();
                            }
                            final cfi = payload['cfi'];
                            if (cfi is String && cfi.isNotEmpty) {
                              _location = cfi;
                            }
                            _scheduleSave();
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowReady',
                          callback: (_) {
                            if (!mounted) return;
                            setState(() => _booting = false);
                            _seedAnnotations();
                            if (batteryHook && batteryNoteFlow == 'epub') {
                              _batteryNoteFlow();
                            }
                            if (batteryHook && batterySearchTerm.isNotEmpty) {
                              _openSearch();
                              _searchCtrl.text = batterySearchTerm;
                              _onSearchQuery(batterySearchTerm);
                            }
                            if (batteryHook && batteryDictWord.isNotEmpty) {
                              _dictDebounce?.cancel();
                              _dictDebounce = Timer(
                                const Duration(milliseconds: 800),
                                () => _openDictionary(batteryDictWord),
                              );
                            }
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowSelection',
                          callback: (args) {
                            if (!mounted) return;
                            final payload = args.isNotEmpty
                                ? args.first as Map
                                : const <String, dynamic>{};
                            final text = payload['text'] as String? ?? '';
                            final cfi = payload['cfi'] as String?;
                            if (text.isEmpty) return;
                            // Single-word selections open the dictionary;
                            // longer selections become highlight/note flows
                            // (when the engine can anchor them).
                            final word = sanitizeLookupWord(text);
                            if (word == null || word.isEmpty) return;
                            final wordCount =
                                text.trim().split(RegExp(r'\s+')).length;
                            if (wordCount <= 1) {
                              _dictDebounce?.cancel();
                              _dictDebounce = Timer(
                                const Duration(milliseconds: 300),
                                () => _openDictionary(word),
                              );
                            } else if (cfi != null &&
                                cfi.isNotEmpty &&
                                widget.doc != null) {
                              setState(() => _selAction = (text: text, cfi: cfi));
                            }
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowAnnotationTap',
                          callback: (args) {
                            if (!mounted) return;
                            final payload = args.isNotEmpty
                                ? args.first as Map
                                : const <String, dynamic>{};
                            final uuid = payload['uuid'] as String?;
                            if (uuid == null || uuid.isEmpty) return;
                            _openAnnotationEditor(uuid);
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowError',
                          callback: (args) {
                            final info = args.isEmpty ? '' : '${args.first}';
                            if (mounted) {
                              setState(() => _error = info);
                            }
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowSearchStart',
                          callback: (_) {
                            if (!mounted || !_searchOpen) return;
                            setState(() {
                              _searching = true;
                              _searchCount = 0;
                            });
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowSearchProgress',
                          callback: (args) {
                            if (!mounted || !_searchOpen || !_searching) return;
                            final payload = args.isNotEmpty
                                ? args.first as Map
                                : const <String, dynamic>{};
                            final n = (payload['count'] as num?)?.toInt() ?? 0;
                            setState(() => _searchCount = n);
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowSearchResults',
                          callback: (args) {
                            if (!mounted) return;
                            final payload = args.isNotEmpty
                                ? args.first as Map
                                : const <String, dynamic>{};
                            final raw = payload['results'];
                            final hits = <ReflowHit>[
                              for (final m in (raw is List ? raw : const []))
                                if (m is Map && m['cfi'] is String)
                                  ReflowHit(
                                    cfi: m['cfi'] as String,
                                    pre: '${m['pre'] ?? ''}',
                                    hit: '${m['hit'] ?? ''}',
                                    post: '${m['post'] ?? ''}',
                                  ),
                            ];
                            if (_searchOpen &&
                                _hits.isEmpty &&
                                hits.isEmpty &&
                                payload['failed'] != null) {
                            }
                            setState(() {
                              _searching = false;
                              _searchFailed = payload['failed'] != null;
                              _hits = hits;
                              _hitIdx = hits.isEmpty ? 0 : _hitIdx;
                            });
                          },
                        );
                      },
                      onLoadStop: (_, _) =>
                          setState(() => _booting = false),
                      onConsoleMessage: (_, msg) {
                        debugPrint(
                            '[console/${msg.messageLevel}] ${msg.message}');
                      },
                      shouldOverrideUrlLoading: (_, action) async {
                        final uri = action.request.url;
                        if (uri == null ||
                            !uri.scheme.startsWith('http')) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      },
                    );
                  },
                ),
                if (_booting && _error == null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: cs.surface,
                      child: _PulseLoader(cs: cs),
                    ),
                  ),
                if (_selAction != null)
                  Positioned(
                    left: Dv.sp16,
                    right: Dv.sp16,
                    bottom: Dv.sp12,
                    child: _SelectionActionBar(
                      excerpt: _selAction!.text,
                      onColor: _createReflowHighlight,
                      onNote: _createReflowNote,
                      onClose: _dismissSelAction,
                    ),
                  ),
              ],
            ),
          ),
          ReaderBottomBar(
            current: _permilleViewed ?? 0,
            total: 1000,
            cs: cs,
            onPage: (v) {
              setState(() => _permilleViewed = v);
              final f = v / 1000;
              _fraction = f;
              _scheduleSave();
              _web?.evaluateJavascript(
                  source: 'window.docviewGoToFraction($f)');
            },
            colorMode: _colorMode,
            onColorCycle: _cycleColorMode,
            onSearchOpen: _openSearch,
            onOutline: _showOutline,
            fractionMode: true,
            searchEnabled: true,
          ),
        ],
      ),
    );
  }
}

class _PulseLoader extends StatelessWidget {
  const _PulseLoader({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: Dv.sp16),
            const Text('Opening…'),
          ],
        ),
      );
}

/// Floating bar over the webview while a multi-word selection is active:
/// tap a color to highlight, the note icon to create a note annotation.
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.excerpt,
    required this.onColor,
    required this.onNote,
    required this.onClose,
  });

  final String excerpt;
  final ValueChanged<String> onColor;
  final VoidCallback onNote;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.inverseSurface,
      borderRadius: BorderRadius.circular(Dv.rLg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Dv.sp12, Dv.sp8, Dv.sp12, Dv.sp8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                excerpt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onInverseSurface),
              ),
            ),
            const SizedBox(width: Dv.sp8),
            for (final entry in annotationHex.entries)
              Padding(
                padding: const EdgeInsets.only(right: Dv.sp8),
                child: InkWell(
                  onTap: () => onColor(entry.key),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF000000 |
                          int.parse(entry.value.substring(1), radix: 16)),
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: Icon(Icons.sticky_note_2_outlined,
                  color: cs.onInverseSurface),
              tooltip: 'Add note',
              onPressed: onNote,
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: cs.onInverseSurface),
              tooltip: 'Dismiss',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// One search hit from the foliate search bridge (excerpt already clipped).
class ReflowHit {
  const ReflowHit({
    required this.cfi,
    required this.pre,
    required this.hit,
    required this.post,
  });

  final String cfi;
  final String pre;
  final String hit;
  final String post;
}

class _HitExcerpt extends StatelessWidget {
  const _HitExcerpt({required this.hit});

  final ReflowHit hit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
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
    );
  }
}
