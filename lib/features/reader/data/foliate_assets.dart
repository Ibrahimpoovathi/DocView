import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/paths/app_paths.dart';
import 'book_server.dart';

/// Installs the bundled foliate-js tree into the app sandbox and tells the
/// BookServer where to serve it from. Cheap to call repeatedly (no-ops after
/// first success).
Future<void> installFoliateAssets() async {
  final rootDir =
      Directory(p.join(AppPaths.booksDir.parent.path, 'foliate'));
  final doneMarker = File(p.join(rootDir.path, 'installed.marker'));
  if (!await doneMarker.exists()) {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where((a) => a.startsWith('assets/foliate/'))
        // Hidden files (.git*) exist in the manifest but are not loadable.
        .where((a) => !p.basename(a).startsWith('.'))
        .toList();

    for (final asset in assets) {
      final rel = asset.replaceFirst('assets/foliate/', '');
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes,
          data.lengthInBytes);
      final file = File(p.join(rootDir.path, rel));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    await doneMarker.create();
  }
  BookServer.useFoliateDirectory(rootDir);
}