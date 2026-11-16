import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/paths/app_paths.dart';
import 'core/storage/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  // Engine init for background metadata/cover work outside the viewer widget.
  await pdfrx.pdfrxFlutterInitialize();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const DocViewApp(),
  ));
}
