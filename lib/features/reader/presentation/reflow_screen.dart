// ignore_for_file: avoid_print
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/design/dv.dart';
import '../../../core/paths/app_paths.dart';
import '../../../core/design/widgets/empty_state.dart';
import '../../../core/format/doc_format.dart';
import '../../../core/storage/database.dart';
import '../data/book_server.dart';
import '../data/foliate_assets.dart';
import '../../library/presentation/providers.dart';
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
  ViewerColorMode _colorMode = ViewerColorMode.normal;

  Document? get _doc => widget.doc;
  bool get _canSave => widget.doc != null;

  String _title() => _doc?.title ?? widget.debugTitle;

  @override
  void initState() {
    super.initState();
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
    unawaited(BookServer.stop());
    super.dispose();
  }

  Future<void> _flushSave() async {
    if (!_canSave) return;
    _saveDebounce?.cancel();
    await ref
        .read(readingRepositoryProvider)
        .saveProgress(_doc!.id, _fraction, _location);
  }

  Future<void> _prepare() async {
    // Restore color mode + last position before building the webview URL.
    if (widget.doc != null) {
      final pos =
          await ref.read(readingRepositoryProvider).ensure(widget.doc!.id);
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
      _bookUrlFuture ??= _bookUrl().then((u) {
        print('[reflow] url=$u');
        return u;
      }).catchError((Object e) {
        print('[reflow] ERROR $e');
        // ignore: invalid_use_of_protected_member
        setState(() => _error = e.toString());
        throw e;
      });

  Future<WebUri> _bookUrl() async {
    await installFoliateAssets();
    final port = await BookServer.ensureRunning();
    final base = 'http://127.0.0.1:$port';

    final String sourceUrl;
    if (widget.debugPath != null) {
      sourceUrl =
          '$base/files/${p.split(widget.debugPath!).last}';
    } else {
      final rel = p
          .relative(widget.doc!.storedPath,
              from: AppPaths.booksDir.path)
          .replaceAll(r'\', '/');
      final enc = rel.split('/').map(Uri.encodeComponent).join('/');
      sourceUrl = _doc!.format == DocFormat.txt
          ? '$base/txt/$enc'
          : '$base/files/$enc';
    }

    final q = StringBuffer(
        '$base/foliate/docview.html?src=${Uri.encodeComponent(sourceUrl)}'
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
      ref
          .read(readingRepositoryProvider)
          .saveProgress(_doc!.id, _fraction, _location);
    });
  }

  Future<void> _cycleColorMode() async {
    final next = ViewerColorMode
        .values[(_colorMode.index + 1) % ViewerColorMode.values.length];
    setState(() {
      _colorMode = next;
      _booting = false; // keep chrome; webview reloads
      _error = null;
    });
    _bookUrlFuture = null; // rebuild webview url with the new color
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
      ),
      body: Column(
        children: [
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
                      key: ValueKey(_colorMode),
                      initialUrlRequest: URLRequest(url: snap.data!),

                      initialSettings: InAppWebViewSettings(
                        transparentBackground: false,
                        supportZoom: true,
                        useHybridComposition: true,
                      ),
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
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'onReflowError',
                          callback: (args) {
                            final info = args.isEmpty ? '' : '${args.first}';
                            print('[reflow] page error: $info');
                            if (mounted) {
                              setState(() => _error = info);
                            }
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
            onSearchOpen: () {},
            onOutline: _showOutline,
            fractionMode: true,
            searchEnabled: false,
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
