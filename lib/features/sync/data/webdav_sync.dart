import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webdav_client_plus/webdav_client_plus.dart';

/// WebDAV account as entered in Settings.
class WebdavAccount {
  final String url;
  final String user;
  final String password;

  const WebdavAccount({
    required this.url,
    required this.user,
    required this.password,
  });

  bool get isComplete =>
      url.trim().isNotEmpty && user.trim().isNotEmpty && password.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'url': url,
        'user': user,
        'password': password,
      };

  static WebdavAccount? fromJson(Map<String, dynamic> json) {
    final url = json['url'] as String?;
    final user = json['user'] as String?;
    final password = json['password'] as String?;
    if (url == null || user == null || password == null) return null;
    if (url.trim().isEmpty) return null;
    return WebdavAccount(url: url, user: user, password: password);
  }
}

const String basePath = 'DocView';

/// Stores the WebDAV account (incl. password) encrypted on-device.
class WebdavCredentialStore {
  static const _key = 'docview.webdav.account';
  final FlutterSecureStorage _storage;

  WebdavCredentialStore() : _storage = const FlutterSecureStorage();

  Future<WebdavAccount?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return WebdavAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(WebdavAccount account) =>
      _storage.write(key: _key, value: jsonEncode(account.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}

/// Remote operations the sync engine needs (implemented over WebDAV in
/// production; faked in tests).
abstract class WebdavBackend {
  Future<void> ensureDirs();
  Future<Map<String, dynamic>?> readManifest();
  Future<void> writeManifest(Map<String, dynamic> manifest);
  Future<Map<String, int>> listBooks();
  Future<Set<String>> listCoverShas();
  Future<Uint8List> readBook(String remoteName,
      {void Function(int, int)? onProgress});
  Future<void> writeBook(String remoteName, File localFile,
      {void Function(int, int)? onProgress});
  Future<Uint8List?> readCover(String sha256);
  Future<void> writeCover(String sha256, Uint8List bytes);
}

/// Thin wrapper over webdav_client_plus for DocView's remote layout:
/// `<base>/DocView/manifest.json`, `<base>/DocView/books/<sha256>__<name>`,
/// `<base>/DocView/covers/<sha256>.jpg`.
class DocviewWebdav implements WebdavBackend {
  static const _root = basePath;
  static const _booksDir = '$_root/books';
  static const _coversDir = '$_root/covers';
  static const _manifestPath = '$_root/manifest.json';

  final WebdavClient _client;

  DocviewWebdav._(this._client);

  factory DocviewWebdav.fromAccount(WebdavAccount account) {
    var url = account.url.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final client = WebdavClient.basicAuth(
      url: url,
      user: account.user,
      pwd: account.password,
      options: const WebdavOptions(
        connectTimeout: Duration(seconds: 20),
        sendTimeout: Duration(minutes: 5),
        receiveTimeout: Duration(minutes: 5),
      ),
    );
    return DocviewWebdav._(client);
  }

  /// PROPFIND on the base URL. Throws on bad credentials / unreachable host.
  Future<void> testConnection() async {
    await _client.readProps('/');
  }

  /// Creates /DocView/, books/ and covers/ (no-ops when they exist).
  @override
  Future<void> ensureDirs() async {
    await _client.mkdirAll(_root);
    await _client.mkdirAll(_booksDir);
    await _client.mkdirAll(_coversDir);
  }

  /// Reads manifest.json; null when not present yet (first sync).
  @override
  Future<Map<String, dynamic>?> readManifest() async {
    try {
      final bytes = await _client.read(_manifestPath);
      final raw = utf8.decode(bytes);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } on WebdavException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> writeManifest(Map<String, dynamic> manifest) =>
      _client.write(_manifestPath, Uint8List.fromList(utf8.encode(jsonEncode(manifest))));

  /// Books currently on the server, keyed by file name (sha256__orig).
  @override
  Future<Map<String, int>> listBooks() async {
    final out = <String, int>{};
    try {
      final files = await _client.readDir(_booksDir);
      for (final f in files) {
        if (!f.isDir) out[f.name] = f.size ?? 0;
      }
    } on WebdavException catch (e) {
      if (e.statusCode == 404) return out;
      rethrow;
    }
    return out;
  }

  /// Cover files on the server as a set of sha256 keys.
  @override
  Future<Set<String>> listCoverShas() async {
    final out = <String>{};
    try {
      final files = await _client.readDir(_coversDir);
      for (final f in files) {
        if (f.isDir) continue;
        final sha = f.name;
        if (sha.endsWith('.jpg')) out.add(sha.substring(0, sha.length - 4));
      }
    } on WebdavException catch (e) {
      if (e.statusCode == 404) return out;
      rethrow;
    }
    return out;
  }

  /// True when books/ contains any file whose name starts with [sha256].
  Future<bool> hasBook(String sha256) async {
    final books = await listBooks();
    return books.keys.any((name) => _shaOf(name) == sha256);
  }

  @override
  Future<Uint8List> readBook(String remoteName, {void Function(int, int)? onProgress}) =>
      _client.read('$_booksDir/$remoteName', onProgress: onProgress);

  @override
  Future<void> writeBook(String remoteName, File localFile,
          {void Function(int, int)? onProgress}) =>
      _client.writeFile(localFile.path, '$_booksDir/$remoteName',
          onProgress: onProgress);

  @override
  Future<Uint8List?> readCover(String sha256) async {
    try {
      return await _client.read('$_coversDir/$sha256.jpg');
    } on WebdavException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> writeCover(String sha256, Uint8List bytes) =>
      _client.write('$_coversDir/$sha256.jpg', bytes);

  static String _shaOf(String remoteName) {
    final i = remoteName.indexOf('__');
    return i <= 0 ? remoteName : remoteName.substring(0, i);
  }
}
