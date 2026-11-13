import 'package:flutter/material.dart';
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

/// Battery-only: WebDAV sync URL auto-configured at boot
/// (`--dart-define=DOCVIEW_BATTERY_SYNC=http://10.0.2.2:8080/dav/`).
/// Credentials are fixed battery dummies; empty disables the sync battery.
const batterySyncUrl = String.fromEnvironment('DOCVIEW_BATTERY_SYNC');

/// Battery-only: annotation flow on reader open
/// (`--dart-define=DOCVIEW_BATTERY_NOTE=epub`). Simulates a multi-word
/// selection in the reflow reader, creates a highlight + note + bookmark,
/// then opens the annotations list for screenshot verification.
const batteryNoteFlow = String.fromEnvironment('DOCVIEW_BATTERY_NOTE');

/// Battery-only: inflate the library with N cheap TXT docs
/// (`--dart-define=DOCVIEW_BATTERY_BIGLIB=200`) to profile big-library
/// performance. The run ends on the library grid (no reader auto-open).
/// 0 disables.
const batteryBigLib = int.fromEnvironment('DOCVIEW_BATTERY_BIGLIB');

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
    ShellRoute(
      // Wide-screen 2-pane: on ≥840dp the library stays live on the left
      // while the reader fills the right pane; narrow = full-screen reader.
      builder: (context, state, navigator) => _ReaderShell(navigator: navigator),
      routes: [
        GoRoute(
          path: '/reader/:docId',
          builder: (context, state) => ReaderScreen(
            docId: int.parse(state.pathParameters['docId']!),
          ),
        ),
      ],
    ),
    if (batteryHook)
      ShellRoute(
        builder: (context, state, navigator) =>
            _ReaderShell(navigator: navigator),
        routes: [
          GoRoute(
            path: '/reader-debug/raw',
            builder: (context, state) => ReaderScreen(
              docId: 0,
              debugPath: state.uri.queryParameters['path'],
            ),
          ),
        ],
      ),
  ],
);

/// Wide-screen 2-pane reader shell. Below 840dp the reader takes the whole
/// screen; on wide screens the library stays interactive in a fixed-width
/// left pane (open another book to swap the right pane instantly).
class _ReaderShell extends StatelessWidget {
  const _ReaderShell({required this.navigator});

  final Widget navigator;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (!wide) return navigator;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 372, child: LibraryScreen()),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: navigator),
      ],
    );
  }
}
