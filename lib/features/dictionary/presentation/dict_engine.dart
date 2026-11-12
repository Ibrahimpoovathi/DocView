/// Hidden WebView engine that runs `dictview.html` (StarDict lookup) served
/// by the BookServer. Must be mounted in the widget tree (1×1 px, invisible);
/// lookups are issued via [DictEngineController.lookup].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/dict_registry.dart';
import '../../reader/data/book_server.dart';
import '../../reader/data/foliate_assets.dart';

/// Orchestrates the hidden WebView; owned by the UI that triggers lookups.
class DictEngineController {
  InAppWebViewController? _web;

  /// Currently loaded dictionary id (or null until a dict page finishes
  /// initializing).
  String? _loadedId;
  String? loadedBookName;

  /// Pending result completers keyed by request id.
  final _pending = <int, Completer<String?>>{};
  int _reqSeq = 0;

  void attach(InAppWebViewController web) => _web = web;

  /// Called by the widget when JS reports the dict page finished loading
  /// (`onDictReady`) or failed (`onDictError`).
  void markReady(String bookName) {
    loadedBookName = bookName;
    final c = _loading;
    if (c != null && !c.isCompleted) c.complete();
  }

  void markError(String error) {
    final c = _loading;
    if (c != null && !c.isCompleted) c.completeError(Exception(error));
  }

  /// True when an imported dictionary is configured.
  bool get hasDictionary => _imported != null;
  ImportedDict? _imported;

  /// Sets the active dictionary (call whenever the registry changes).
  void setImported(ImportedDict? imported) {
    if (imported?.id != _imported?.id) invalidate();
    _imported = imported;
  }

  /// Requests [word] from the loaded StarDict dictionary.
  /// Returns null when no dictionary is configured/loaded or nothing hit.
  Future<String?> lookup(String word) async {
    final imported = _imported;
    if (imported == null) return null;
    await _ensureLoaded(imported);
    final reqId = ++_reqSeq;
    final completer = Completer<String?>();
    _pending[reqId] = completer;
    await _web?.evaluateJavascript(
      source: 'window.dictLookup($reqId, ${jsonEncode(word)})',
    );
    return completer.future;
  }

  Completer<void>? _loading;

  Future<void> _ensureLoaded(ImportedDict imported) async {
    if (_loadedId == imported.id) return;
    if (_loading != null) await _loading!.future;
    if (_loadedId == imported.id) return;
    final ready = Completer<void>();
    _loading = ready;
    _imported = imported;
    try {
      // dictview.html ships inside the foliate asset bundle — make sure it
      // is installed even when no reflow reader has ever been opened.
      await installFoliateAssets();
      final port = await BookServer.ensureRunning();
      final base = 'http://127.0.0.1:$port';
      final url =
          '$base/foliate/dictview.html?name=${Uri.encodeComponent(imported.id)}';
      await _web?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
      await ready.future.timeout(const Duration(seconds: 12));
      _loadedId = imported.id;
    } finally {
      _loading = null;
    }
  }

  /// Called by the widget's JS handler `onDictResult`.
  void handleResult(Map<String, Object?> payload) {
    final id = (payload['id'] as num?)?.toInt();
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (payload['ok'] == true) {
      final text = payload['text'] as String? ?? '';
      completer.complete(text.trim().isEmpty ? null : text);
    } else {
      completer.complete(null);
    }
  }

  /// Clears the loaded state so the next lookup reloads the (possibly
  /// changed) dictionary page.
  void invalidate() {
    _loadedId = null;
    loadedBookName = null;
  }
}

class DictEngine extends StatefulWidget {
  const DictEngine({super.key, required this.controller});

  final DictEngineController controller;

  @override
  State<DictEngine> createState() => _DictEngineState();
}

class _DictEngineState extends State<DictEngine> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0,
        child: InAppWebView(
            initialData: InAppWebViewInitialData(
              data: '<html><body></body></html>',
              mimeType: 'text/html',
              encoding: 'utf-8',
            ),
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              useHybridComposition: true,
            ),
            onWebViewCreated: (c) {
              widget.controller.attach(c);
              c.addJavaScriptHandler(
                handlerName: 'onDictReady',
                callback: (args) {
                  final payload =
                      args.isNotEmpty ? args.first as Map : const {};
                  widget.controller
                      .markReady('${payload['bookName'] ?? ''}');
                  return null;
                },
              );
              c.addJavaScriptHandler(
                handlerName: 'onDictError',
                callback: (args) {
                  widget.controller
                      .markError(args.isEmpty ? 'unknown' : '${args.first}');
                  return null;
                },
              );
              c.addJavaScriptHandler(
                handlerName: 'onDictResult',
                callback: (args) {
                  final payload = args.isNotEmpty
                      ? (args.first as Map).cast<String, Object?>()
                      : const <String, Object?>{};
                  widget.controller.handleResult(payload);
                  return null;
                },
              );
            },
          ),
        ),
      );
  }
}
