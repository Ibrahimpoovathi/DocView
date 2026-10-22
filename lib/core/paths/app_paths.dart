import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Deterministic app-owned storage layout:
/// - `books/<uuid>/orig.<ext>` — sandboxed copy of the source document
/// - `covers/<uuid>.jpg`       — generated cover art
abstract final class AppPaths {
  static Directory? _books;
  static Directory? _covers;

  static Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    initForTest(support);
  }

  /// Test hook (no path_provider plugin in `flutter test`).
  static void initForTest(Directory support) {
    _books = Directory(p.join(support.path, 'books'))..createSync(recursive: true);
    _covers = Directory(p.join(support.path, 'covers'))..createSync(recursive: true);
  }

  static Directory get booksDir =>
      _books ?? (throw StateError('AppPaths.init() not called'));

  static Directory get coversDir =>
      _covers ?? (throw StateError('AppPaths.init() not called'));

  static String bookFilePath(String uuid, String originalName) => p.join(
        booksDir.path,
        uuid,
        'orig.${p.extension(originalName).replaceFirst('.', '').toLowerCase()}',
      );

  static String coverFilePath(String uuid) =>
      p.join(coversDir.path, '$uuid.jpg');

  /// Removes the whole book directory for a document (called on delete).
  static Future<void> deleteBookDir(String uuid) async {
    final dir = Directory(p.join(booksDir.path, uuid));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes a cover file if present (called on delete/cover refresh).
  static Future<void> deleteCover(String uuid) async {
    final f = File(coverFilePath(uuid));
    if (await f.exists()) await f.delete();
  }
}
