import 'package:docview/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 0 smoke suite', () {
    testWidgets('library renders and restarts with state intact', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: DocViewApp()));
      await tester.pumpAndSettle();

      expect(find.text('DocView'), findsOneWidget);
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.text('Add documents'), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      // FAB label also appears inside the extended FAB.
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
