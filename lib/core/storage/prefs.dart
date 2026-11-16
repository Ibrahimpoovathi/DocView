import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single SharedPreferences instance, loaded once in `main()` and injected
/// as an override. Everything that reads or writes prefs goes through this
/// provider, so the app performs exactly one platform-channel round-trip
/// instead of one per setting interaction.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);
