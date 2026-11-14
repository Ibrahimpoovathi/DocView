import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../../core/paths/app_paths.dart';
import 'fb2_to_epub.dart';
import 'txt_to_epub.dart';

/// App-owned local HTTP server for the reflow reader (foliate-js).
///
/// Serves:
/// - `/foliate/**` — bundled JS/HTML (installed from assets to the app dir)
/// - `/files/<path>` — files stored under the sandbox books directory
///
/// Bound to the loopback interface only; nothing leaves the device.
class BookServer {
  BookServer._();

  static HttpServer? _server;
  static int? _port;
  static Directory? _foliateDir;

  /// Where foliate-html was installed (set by [installFoliateAssets]).
  static void useFoliateDirectory(Directory dir) => _foliateDir = dir;

  /// Starts (or returns an already-running) server; returns its port.
  static Future<int> ensureRunning() async {
    if (_server != null) return _port!;
    final server = await shelf_io.serve(
      _buildRouter().call,
      InternetAddress.loopbackIPv4,
      0,
      poweredByHeader: null,
    );
    _server = server;
    _port = server.port;
    return server.port;
  }

  static Future<void> stop() async {
    final s = _server;
    _server = null;
    _port = null;
    await s?.close(force: true);
  }

  static Router _buildRouter() {
    final router = Router();

    router.get('/foliate/<path|.*>', (Request req) async {
      final dir = _foliateDir;
      if (dir == null) return Response.internalServerError(body: 'foliate not installed');
      final file = _inside(dir, req.params['path'] ?? '');
      if (file == null || !await file.exists()) return Response.notFound('not found');
      return _ok(
          await file.readAsBytes(),
          _contentTypeFor(file.path,
              fallback: 'application/octet-stream'));
    });

    router.get('/files/<path|.*>', (Request req) async {
      final file = _inside(AppPaths.booksDir, req.params['path'] ?? '');
      if (file == null || !await file.exists()) {
        return Response.notFound('not found');
      }
      // foliate-js reads the whole file into a Blob; partial content is not
      // needed but declared so zip.js stays on the plain path. Stream the
      // file so a 50MB book never materialises fully in RAM per request.
      final len = await file.length();
      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type':
              _contentTypeFor(file.path, fallback: 'application/octet-stream'),
          'Content-Length': '$len',
          'Cache-Control': 'no-store',
        },
      );
    });

    router.get('/dicts/<path|.*>', (Request req) async {
      final file = _inside(AppPaths.dictsDir, req.params['path'] ?? '');
      if (file == null || !await file.exists()) {
        return Response.notFound('not found');
      }
      return _ok(
          await file.readAsBytes(),
          _contentTypeFor(file.path,
              fallback: 'application/octet-stream'));
    });

    router.get('/txt/<path|.*>', (Request req) async {
      // Plain text — convert to a generated EPUB on the fly (cached).
      // Conversion used to run synchronously on the main isolate: a 50MB
      // txt froze the UI for minutes and never finished. Now: size guard +
      // background isolate + bounded LRU cache.
      final file = _inside(AppPaths.booksDir, req.params['path'] ?? '');
      if (file == null || !await file.exists()) {
        return Response.notFound('not found');
      }
      final size = await file.length();
      if (size > maxTxtConvertBytes) {
        // Friendly in-reader page instead of an error the fetch layer can't
        // describe: foliate renders this tiny EPUB like any other book.
        return _ok(txtTooLargeEpub(size), 'application/epub+zip');
      }
      final cacheKey = '${file.path}#${await file.lastModified()}';
      final cached = _convertCacheGet(cacheKey);
      if (cached != null) return _ok(cached, 'application/epub+zip');
      final path = file.path;
      final converted = await Isolate.run(() {
        final f = File(path);
        return txtToEpub(f.readAsBytesSync());
      });
      _convertCachePut(cacheKey, converted);
      return _ok(converted, 'application/epub+zip');
    });

    router.get('/fb2/<path|.*>', (Request req) async {
      // FictionBook 2 → generated EPUB on the fly (cached, background
      // isolate). foliate-js's in-renderer fb2.js crashed the WebView
      // renderer during the audit battery; conversion now happens in Dart.
      final file = _inside(AppPaths.booksDir, req.params['path'] ?? '');
      if (file == null || !await file.exists()) {
        return Response.notFound('not found');
      }
      final cacheKey = '${file.path}#${await file.lastModified()}';
      final cached = _convertCacheGet(cacheKey);
      if (cached != null) return _ok(cached, 'application/epub+zip');
      final path = file.path;
      final converted = await Isolate.run(() {
        final f = File(path);
        return fb2ToEpub(f.readAsBytesSync());
      });
      _convertCachePut(cacheKey, converted);
      return _ok(converted, 'application/epub+zip');
    });

    return router;
  }

  /// Above this size plain text is refused with a friendly in-reader page
  /// instead of freezing the reader (conversion cost grows superlinearly).
  static const maxTxtConvertBytes = maxTxtConvertMb * 1024 * 1024;

  static const _maxConvertCacheEntries = 4;

  /// LRU over on-the-fly conversions (txt→EPUB, fb2→EPUB). Results are
  /// re-derivable; a handful of entries keeps repeat opens instant.
  static final Map<String, Uint8List> _convertCache = {};

  static Uint8List? _convertCacheGet(String key) {
    final value = _convertCache.remove(key);
    if (value != null) _convertCache[key] = value;
    return value;
  }

  static void _convertCachePut(String key, Uint8List value) {
    _convertCache[key] = value;
    while (_convertCache.length > _maxConvertCacheEntries) {
      _convertCache.remove(_convertCache.keys.first);
    }
  }

  static void clearTxtCache() => _convertCache.clear();

  static File? _inside(Directory root, String rel) {
    final rootAbs = p.normalize(p.absolute(root.path));
    final candAbs = p.normalize(p.absolute(p.join(rootAbs, rel)));
    if (!candAbs.startsWith('$rootAbs/')) return null;
    return File(candAbs);
  }

  static Response _ok(List<int> bytes, String contentType) => Response.ok(
        bytes,
        headers: {
          'Content-Type': contentType,
          'Content-Length': '${bytes.length}',
          'Cache-Control': 'no-store',
        },
      );

  static String _contentTypeFor(String path, {required String fallback}) {
    final ext = p.extension(path).toLowerCase();
    const map = {
      '.html': 'text/html; charset=utf-8',
      '.js': 'text/javascript',
      '.mjs': 'text/javascript',
      '.css': 'text/css',
      '.json': 'application/json',
      '.svg': 'image/svg+xml',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.woff': 'font/woff',
      '.woff2': 'font/woff2',
      '.epub': 'application/epub+zip',
      '.mobi': 'application/x-mobipocket-ebook',
      '.azw3': 'application/vnd.amazon.ebook',
      '.fb2': 'application/x-fictionbook+xml',
      '.cbz': 'application/vnd.comicbook+zip',
      '.txt': 'text/plain; charset=utf-8',
    };
    return map[ext] ?? fallback;
  }
}
