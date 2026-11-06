
import 'package:docview/app/app.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('library screen renders empty state', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const DocViewApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('DocView'), findsOneWidget);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Pick files'), findsOneWidget);

    await db.close();
  });
}
