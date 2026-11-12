import 'package:go_router/go_router.dart';

import '../../features/dictionary/presentation/settings_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/reader/presentation/reader_screen.dart';

/// Battery hook: ADDED only in builds made with
/// `--dart-define=DOCVIEW_BATTERY=true`. The shipped APK stays clean.
const batteryHook =
    bool.fromEnvironment('DOCVIEW_BATTERY', defaultValue: false);

/// Battery build can pin which seed format auto-opens first
/// (`--dart-define=DOCVIEW_BATTERY_OPEN=xlsx` etc.) so the battery can
/// exercise each reader. Empty = default docx-first priority.
const batteryOpenFormat = String.fromEnvironment('DOCVIEW_BATTERY_OPEN');

/// Battery-only: term injected into the in-document search when a document
/// opens (`--dart-define=DOCVIEW_BATTERY_SEARCH=word`). Empty disables it.
const batterySearchTerm = String.fromEnvironment('DOCVIEW_BATTERY_SEARCH');

/// Battery-only: word auto-looked-up in the dictionary popup when a reader
/// opens (`--dart-define=DOCVIEW_BATTERY_DICT=word`). Empty disables it.
const batteryDictWord = String.fromEnvironment('DOCVIEW_BATTERY_DICT');

final router = GoRouter(
  initialLocation: '/library',
  routes: [
    GoRoute(
      path: '/library',
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/reader/:docId',
      builder: (context, state) => ReaderScreen(
        docId: int.parse(state.pathParameters['docId']!),
      ),
    ),
    if (batteryHook)
      GoRoute(
        path: '/reader-debug/raw',
        builder: (context, state) => ReaderScreen(
          docId: 0,
          debugPath: state.uri.queryParameters['path'],
        ),
      ),
  ],
);
