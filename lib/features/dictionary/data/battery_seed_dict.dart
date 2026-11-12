/// Battery-only: seeds a tiny StarDict dictionary in the sandbox so the
/// offline lookup path can be exercised on emulators without a UI import.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/paths/app_paths.dart';
import 'dict_registry.dart';

const _batteryWords = <String, String>{
  'battery': 'A device that stores energy and produces electric current.',
  'silver': 'A precious greyish-white metal, or the colour of it.',
  'ribbon': 'A long narrow strip of fabric used for decoration.',
  'test': 'A procedure to establish quality or performance.',
};

/// Creates and registers the seed dictionary. No-op when a seed already
/// exists (deterministic id keeps battery runs idempotent).
Future<void> seedBatteryStarDict() async {
  final dir = Directory(p.join(AppPaths.dictsDir.path, 'battery-seed'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);

    // Build the plain dict data and index.
    final dictOut = BytesBuilder();
    final idxOut = BytesBuilder();
    final sortedWords = _batteryWords.keys.toList()..sort();
    for (final word in sortedWords) {
      final article = utf8.encode(_batteryWords[word]!);
      final wordBytes = utf8.encode(word);
      idxOut
        ..add(wordBytes)
        ..add([0])
        ..add([
          (dictOut.length >> 24) & 0xff,
          (dictOut.length >> 16) & 0xff,
          (dictOut.length >> 8) & 0xff,
          dictOut.length & 0xff,
        ])
        ..add([
          (article.length >> 24) & 0xff,
          (article.length >> 16) & 0xff,
          (article.length >> 8) & 0xff,
          article.length & 0xff,
        ]);
      dictOut.add(article);
    }
    final dictBytes = dictOut.toBytes();
    final idxBytes = idxOut.toBytes();
    final ifo = "StarDict's dict ifo file version=2.4.2\n"
        'bookname=Battery Seed\n'
        'wordcount=${_batteryWords.length}\n'
        'idxfilesize=${idxBytes.length}\n'
        'sametypesequence=m\n';

    await File(p.join(dir.path, 'dict.ifo')).writeAsBytes(utf8.encode(ifo));
    await File(p.join(dir.path, 'dict.idx')).writeAsBytes(idxBytes);
    // The engine reads the plain (converted) dict data file: <base>.dict.flat.
    await File(p.join(dir.path, 'dict.dict.flat')).writeAsBytes(dictBytes);
  }

  final prefs = await SharedPreferences.getInstance();
  final registry = DictRegistry(prefs);
  if (registry.list().any((d) => d.id == 'battery-seed')) return;
  await registry.register(ImportedDict(
    id: 'battery-seed',
    bookName: 'Battery Seed',
    dir: dir.path,
    base: 'dict',
    typeSequence: 'm',
    wordCount: '4',
  ));
}
