import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/paths/app_paths.dart';
import 'core/storage/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds render a raised exception as a bare gray surface, which is
  // indistinguishable from a hung/blank reader. Always show something
  // actionable and keep the stack in logcat.
  ErrorWidget.builder = _fatalErrorWidget;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[fatal] ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[fatal] $error\n$stack');
    return true;
  };
  await AppPaths.init();
  // Engine init for background metadata/cover work outside the viewer widget.
  await pdfrx.pdfrxFlutterInitialize();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const DocViewApp(),
  ));
}

Widget _fatalErrorWidget(FlutterErrorDetails details) => Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFF6F1E7),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.error_outline_rounded,
                    size: 40, color: Color(0xFF8A4B2A)),
                SizedBox(height: 12),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B2621),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Please go back and try opening the document again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B625A)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
