import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/prefs.dart';
import '../data/dictionary_service.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
OnlineDictionary onlineDictionary(Ref ref) => OnlineDictionary();

/// History store backed by the single shared_preferences instance.
@Riverpod(keepAlive: true)
LookupHistory lookupHistory(Ref ref) =>
    LookupHistory(ref.watch(sharedPreferencesProvider));
