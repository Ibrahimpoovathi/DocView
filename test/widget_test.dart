import 'package:docview/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('library screen renders empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: DocViewApp()),
    );

    expect(find.text('DocView'), findsOneWidget);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Add documents'), findsOneWidget);
  });
}
