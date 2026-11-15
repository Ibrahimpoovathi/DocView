import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// A file handed to DocView by another app ("Open with" / "Share").
class OpenWithFile {
  const OpenWithFile({
    required this.path,
    required this.name,
    required this.temporary,
  });

  final String path;
  final String name;

  /// True when [path] is a throwaway copy in the app cache that the caller
  /// should delete after importing.
  final bool temporary;
}

/// Receives Android intent hand-offs from [MainActivity].
class OpenWith {
  OpenWith._();

  static final OpenWith instance = OpenWith._();

  static const _channel = MethodChannel('docview/open_with');

  final _files = StreamController<OpenWithFile>.broadcast();
  bool _started = false;

  Stream<OpenWithFile> get files => _files.stream;

  /// Wires up the platform channel and drains any intent that launched the
  /// app. Safe to call repeatedly.
  Future<void> start() async {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpen') await _drain();
    });
    await _drain();
  }

  Future<void> _drain() async {
    List<dynamic>? raw;
    try {
      raw = await _channel.invokeMethod<List<dynamic>>('takePending');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    for (final item in raw ?? const <dynamic>[]) {
      final map = (item as Map).cast<String, Object?>();
      final path = map['path'] as String?;
      if (path == null || path.isEmpty) continue;
      _files.add(OpenWithFile(
        path: path,
        name: (map['name'] as String?) ?? path.split('/').last,
        temporary: (map['temporary'] as bool?) ?? false,
      ));
    }
  }
}
