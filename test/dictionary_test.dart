import 'dart:convert';

import 'package:docview/features/dictionary/data/dictionary_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Realistic dictionaryapi.dev response (trimmed to relevant fields).
const _apiBody = '''
[
  {
    "word": "battery",
    "phonetic": "/ˈbæt.əɹ.i/",
    "phonetics": [
      { "text": "/ˈbæt.əɹ.i/", "audio": "" },
      { "text": "ˈbætəri", "audio": "..." }
    ],
    "meanings": [
      {
        "partOfSpeech": "noun",
        "definitions": [
          {
            "definition": "A device used to produce electric current.",
            "example": "The battery is dead."
          },
          { "definition": "A set of similar things." }
        ]
      },
      {
        "partOfSpeech": "verb",
        "definitions": [{ "definition": "To batter." }]
      }
    ]
  },
  { "word": "battery", "meanings": [] }
]
''';

void main() {
  group('parseDictionaryApiResponse', () {
    test('parses phonetic, meanings, definitions', () {
      final entry = parseDictionaryApiResponse(_apiBody)!;
      expect(entry.word, 'battery');
      expect(entry.phonetic, '/ˈbæt.əɹ.i/');
      expect(entry.meanings, hasLength(2));
      expect(entry.meanings[0].partOfSpeech, 'noun');
      expect(entry.meanings[0].definitions[0].definition,
          'A device used to produce electric current.');
      expect(entry.meanings[0].definitions[0].example, 'The battery is dead.');
      expect(entry.meanings[0].definitions[1].example, isNull);
    });

    test('falls back to first non-empty phonetics[].text when phonetic missing',
        () {
      final entry = parseDictionaryApiResponse('''
[{"word": "x", "phonetics": [{"text": ""}, {"text": "/ks/"}],
  "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "d"}]}]}]
''')!;
      expect(entry.phonetic, '/ks/');
    });

    test('returns null on empty meanings, bad json, non-list', () {
      expect(parseDictionaryApiResponse('[{"word":"x","meanings":[]}]'), isNull);
      expect(parseDictionaryApiResponse('not json'), isNull);
      expect(parseDictionaryApiResponse('{"word":"x"}'), isNull);
      expect(parseDictionaryApiResponse('[]'), isNull);
    });
  });

  group('OnlineDictionary', () {
    test('returns entry on 200 and null on 404', () async {
      final online = OnlineDictionary(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/battery')) {
            // UTF-8: the body contains non-Latin1 phonetic characters and
            // http.Response defaults to latin1 when given a String body.
            return http.Response.bytes(utf8.encode(_apiBody), 200);
          }
          return http.Response('{"title":"No Definitions Found"}', 404);
        }),
      );
      final e1 = await online.lookup('battery');
      expect(e1!.word, 'battery');
      expect(await online.lookup('zzzznope'), isNull);
    });

    test('returns null on network error', () async {
      final online = OnlineDictionary(
        client: MockClient((request) async => throw Exception('offline')),
      );
      expect(await online.lookup('battery'), isNull);
    });
  });

  group('LookupHistory', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('records most-recent-first, deduped case-insensitive', () async {
      final history = LookupHistory(prefs);
      await history.record('Battery');
      await history.record('silver');
      await history.record('battery');
      expect(history.recent(), ['battery', 'silver']);
    });

    test('caps at 30 entries', () async {
      final history = LookupHistory(prefs);
      for (var i = 0; i < 40; i++) {
        await history.record('word$i');
      }
      final recent = history.recent();
      expect(recent, hasLength(30));
      expect(recent.first, 'word39');
      expect(recent.last, 'word10');
    });

    test('clear empties', () async {
      final history = LookupHistory(prefs);
      await history.record('a');
      await history.clear();
      expect(history.recent(), isEmpty);
    });
  });
}
