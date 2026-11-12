import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dictionary_service.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
OnlineDictionary onlineDictionary(Ref ref) => OnlineDictionary();

/// Ready-after-first-load history store (shared_preferences caches values
/// once getInstance resolves).
@Riverpod(keepAlive: true)
Future<LookupHistory> lookupHistory(Ref ref) async =>
    LookupHistory(await SharedPreferences.getInstance());
