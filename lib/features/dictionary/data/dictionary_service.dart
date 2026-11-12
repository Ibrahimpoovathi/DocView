/// Dictionary lookup models + sources.
///
/// Data source 1 (built-in): dictionaryapi.dev online entries.
/// Data source 2 (Phase 6): user-imported StarDict files via dict.js.
///
/// Recent lookups are kept in shared_preferences (JSON list, deduped).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DictionaryDefinition {
  const DictionaryDefinition({required this.definition, this.example});

  factory DictionaryDefinition.fromJson(Map<String, Object?> json) =>
      DictionaryDefinition(
        definition: json['definition'] as String? ?? '',
        example: json['example'] as String?,
      );

  final String definition;
  final String? example;
}

class DictionaryMeaning {
  const DictionaryMeaning({required this.partOfSpeech, required this.definitions});

  factory DictionaryMeaning.fromJson(Map<String, Object?> json) =>
      DictionaryMeaning(
        partOfSpeech: json['partOfSpeech'] as String? ?? '',
        definitions: ((json['definitions'] as List<Object?>?) ?? const [])
            .whereType<Map<String, Object?>>()
            .map(DictionaryDefinition.fromJson)
            .toList(),
      );

  final String partOfSpeech;
  final List<DictionaryDefinition> definitions;
}

class DictionaryEntry {
  const DictionaryEntry({required this.word, this.phonetic, required this.meanings});

  final String word;
  final String? phonetic;
  final List<DictionaryMeaning> meanings;

  bool get isEmpty => meanings.isEmpty;
}

/// Parsed dictionaryapi.dev response (`/api/v2/entries/en/<word>`).
///
/// The API returns a list of entries; we take the first one that yields
/// meanings (later entries are alternate word forms).
DictionaryEntry? parseDictionaryApiResponse(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  for (final item in decoded) {
    if (item is! Map<String, Object?>) continue;
    final meanings = ((item['meanings'] as List<Object?>?) ?? const [])
        .whereType<Map<String, Object?>>()
        .map(DictionaryMeaning.fromJson)
        .where((m) => m.definitions.isNotEmpty)
        .toList();
    if (meanings.isEmpty) continue;
    String? phonetic = item['phonetic'] as String?;
    phonetic ??= ((item['phonetics'] as List<Object?>?) ?? const [])
        .whereType<Map<String, Object?>>()
        .map((p) => p['text'] as String?)
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .toList()
        .firstOrNull;
    return DictionaryEntry(
      word: item['word'] as String? ?? '',
      phonetic: (phonetic == null || phonetic.trim().isEmpty) ? null : phonetic,
      meanings: meanings,
    );
  }
  return null;
}

/// Online lookup against dictionaryapi.dev.
class OnlineDictionary {
  OnlineDictionary({http.Client? client, this.baseUrl = defaultBaseUrl})
      : _client = client ?? http.Client();

  static const defaultBaseUrl = 'https://api.dictionaryapi.dev/api/v2/entries/en';

  final http.Client _client;
  final String baseUrl;

  /// Returns null when the word is not found (404), the network is
  /// unreachable, or the response does not parse.
  Future<DictionaryEntry?> lookup(String word, {Duration timeout = const Duration(seconds: 8)}) async {
    final query = Uri.encodeComponent(word.trim());
    if (query.isEmpty) return null;
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/$query'))
          .timeout(timeout);
      if (response.statusCode != 200 || response.body.isEmpty) return null;
      return parseDictionaryApiResponse(response.body);
    } catch (_) {
      return null;
    }
  }
}

/// Recent-lookup history kept in shared_preferences as a JSON string list.
class LookupHistory {
  LookupHistory(this._prefs);

  static const _key = 'docview.lookupHistory';
  static const _maxEntries = 30;

  final SharedPreferences _prefs;

  List<String> recent() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<String>()
        .where((w) => w.trim().isNotEmpty)
        .toList();
  }
  /// Most-recent-first, deduped (case-insensitive), capped at 30.
  Future<void> record(String word) async {
    final query = word.trim();
    if (query.isEmpty) return;
    final list = List<String>.of(recent())
      ..removeWhere((w) => w.toLowerCase() == query.toLowerCase());
    list.insert(0, query);
    if (list.length > _maxEntries) list.removeRange(_maxEntries, list.length);
    await _prefs.setString(_key, jsonEncode(list));
  }

  Future<void> clear() => _prefs.remove(_key);
}
