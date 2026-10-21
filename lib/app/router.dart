import 'package:go_router/go_router.dart';

import '../features/library/presentation/library_screen.dart';
import '../features/reader/presentation/reader_screen.dart';

final router = GoRouter(
  initialLocation: '/library',
  routes: [
    GoRoute(
      path: '/library',
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: '/reader/:docId',
      builder: (context, state) =>
          ReaderScreen(docId: state.pathParameters['docId']!),
    ),
  ],
);
