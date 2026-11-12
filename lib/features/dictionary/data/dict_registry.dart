/// User-imported StarDict dictionary registry.
///
/// Each dictionary lives in `<appSupport>/dicts/<uuid>/` as:
/// - `<base>.ifo` — metadata (bookname, sametypesequence)
/// - `<base>.idx` — word index
/// - `<base>.dict.flat` — plain dict data (converted from .dict.dz at import)
/// - `<base>.syn` — optional synonyms index
///
/// The registry list is persisted in shared_preferences as JSON.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/paths/app_paths.dart';
import 'dict_zip.dart';

class ImportedDict {
  const ImportedDict({
    required this.id,
    required this.bookName,
    required this.dir,
    required this.base,
    required this.typeSequence,
    required this.wordCount,
  });

  factory ImportedDict.fromJson(Map<String, Object?> json) => ImportedDict(
        id: json['id'] as String,
        bookName: json['bookName'] as String,
        dir: json['dir'] as String,
        base: json['base'] as String,
        typeSequence: json['typeSequence'] as String? ?? 'm',
        wordCount: json['wordCount'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'bookName': bookName,
        'dir': dir,
        'base': base,
        'typeSequence': typeSequence,
        'wordCount': wordCount,
      };

  final String id;

  /// Human-readable dictionary title (from .ifo bookname).
  final String bookName;

  /// Absolute directory containing the dictionary files.
  final String dir;

  /// File base name (without extension) inside [dir].
  final String base;

  /// .ifo sametypesequence (single-letter code).
  final String typeSequence;

  /// .ifo wordcount, informational.
  final String wordCount;

  bool get ready {
    final flat = File(p.join(dir, '$base.dict.flat'));
    final idx = File(p.join(dir, '$base.idx'));
    return flat.existsSync() && idx.existsSync();
  }
}

class DictRegistry {
  DictRegistry(this._prefs);

  static const _key = 'docview.stardict';

  final SharedPreferences _prefs;

  List<ImportedDict> list() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <ImportedDict>[];
    for (final item in decoded) {
      if (item is! Map<String, Object?>) continue;
      try {
        out.add(ImportedDict.fromJson(item));
      } catch (_) {}
    }
    return out.where((d) => d.ready).toList();
  }

  Future<void> _save(List<ImportedDict> dicts) =>
      _prefs.setString(_key, jsonEncode([for (final d in dicts) d.toJson()]));

  /// Registers an already-imported dictionary directory (battery seeding).
  /// Returns false when the files are missing.
  Future<bool> register(ImportedDict imported) async {
    if (!imported.ready) return false;
    final dicts = List<ImportedDict>.of(list())..add(imported);
    await _save(dicts);
    return true;
  }

  /// Imports a StarDict dictionary from picked files.
  ///
  /// [paths] must contain the .ifo and .idx; the dict data may be a plain
  /// .dict or a dictzip-compressed .dict.dz. Returns null on failure.
  Future<ImportedDict?> import({required List<String> paths}) async {
    try {
      final ifo = _find(paths, ['.ifo']);
      final idx = _find(paths, ['.idx']);
      if (ifo == null || idx == null) return null;
      final parsedIfo = StarDictIfo.parse(await File(ifo).readAsString());
      final dict = _find(paths, ['.dict.dz', '.dict']) ?? '';
      if (dict.isEmpty) return null;

      final id =
          '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '${parsedIfo.bookName.hashCode.abs().toRadixString(36)}';
      final dir = Directory(p.join(AppPaths.dictsDir.path, id));
      await dir.create(recursive: true);
      final base = 'dict';

      // Copy index + ifo (normalized to the same base name).
      await File(ifo).copy(p.join(dir.path, '$base.ifo'));
      await File(idx).copy(p.join(dir.path, '$base.idx'));
      final synPath = _find(paths, ['.syn']);
      if (synPath != null) {
        await File(synPath).copy(p.join(dir.path, '$base.syn'));
      }

      // Convert dict data to a plain file the JS side can slice directly.
      final ext = p.extension(dict).toLowerCase();
      final Uint8List flat;
      if (ext == '.dz') {
        flat = inflateDictZip(await File(dict).readAsBytes());
      } else {
        flat = await File(dict).readAsBytes();
      }
      await File(p.join(dir.path, '$base.dict.flat')).writeAsBytes(flat);

      final imported = ImportedDict(
        id: id,
        bookName: parsedIfo.bookName,
        dir: dir.path,
        base: base,
        typeSequence: parsedIfo.sametypesequence,
        wordCount: parsedIfo.wordCount,
      );
      if (!imported.ready) return null;
      final dicts = List<ImportedDict>.of(list())..add(imported);
      await _save(dicts);
      return imported;
    } catch (_) {
      return null;
    }
  }

  Future<bool> remove(String id) async {
    final dicts = list();
    final target = dicts.where((d) => d.id == id).toList();
    if (target.isEmpty) return false;
    final dir = Directory(target.first.dir);
    if (dir.existsSync()) await dir.delete(recursive: true);
    await _save(dicts.where((d) => d.id != id).toList());
    return true;
  }

  String? _find(List<String> paths, List<String> extensions) {
    for (final ext in extensions) {
      for (final path in paths) {
        if (p.extension(path).toLowerCase() == ext) return path;
      }
    }
    return null;
  }
}
