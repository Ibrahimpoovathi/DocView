import 'package:go_router/go_router.dart';

import '../../features/library/presentation/library_screen.dart';
import '../../features/reader/presentation/reader_screen.dart';

/// Battery hook: ADDED only in builds made with
/// `--dart-define=DOCVIEW_BATTERY=true`. The shipped APK stays clean.
const batteryHook =
    bool.fromEnvironment('DOCVIEW_BATTERY', defaultValue: false);

final router = GoRouter(
  initialLocation: '/library',
  routes: [
    GoRoute(
      path: '/library',
      builder: (context, state) => const LibraryScreen(),
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
