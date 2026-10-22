import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import 'app/app.dart';
import 'core/paths/app_paths.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  // Engine init for background metadata/cover work outside the viewer widget.
  await pdfrx.pdfrxFlutterInitialize();
  runApp(const ProviderScope(child: DocViewApp()));
}
