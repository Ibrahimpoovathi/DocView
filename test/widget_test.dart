
import 'package:docview/app/app.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/core/storage/prefs.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('library screen renders empty state', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
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
