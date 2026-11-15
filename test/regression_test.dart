import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docview/core/format/doc_format.dart';
import 'package:docview/core/paths/app_paths.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/data/import_service.dart';
import 'package:docview/features/library/data/library_repository.dart';
import 'package:docview/features/library/data/metadata_service.dart';
import 'package:docview/features/library/domain/library_query.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:docview/features/reader/data/book_server.dart';
import 'package:docview/features/reader/data/docx_pdf.dart';
import 'package:docview/features/reader/data/fb2_to_epub.dart';
import 'package:docview/features/sync/data/sync_manifest.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal but valid .docx: one paragraph plus a Letter-size section.
Uint8List minimalDocx() {
  const document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body><w:p><w:r><w:t>Hello page geometry</w:t></w:r></w:p>'
      '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
      '</w:sectPr></w:body></w:document>';
  const contentTypes = '<?xml version="1.0" encoding="UTF-8"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';
  const rels = '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
  final archive = Archive()
    ..addFile(ArchiveFile('[Content_Types].xml',
        contentTypes.length, utf8.encode(contentTypes)))
    ..addFile(ArchiveFile('_rels/.rels', rels.length, utf8.encode(rels)))
    ..addFile(ArchiveFile('word/document.xml', document.length,
        utf8.encode(document)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('docview-regression');
    AppPaths.initForTest(tmp);
  });

  group('DOCX → PDF', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late Document doc;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepository(db);
      final bytes = minimalDocx();
      final path = AppPaths.bookFilePath('docx-uuid', 'probe.docx');
      await File(path).parent.create(recursive: true);
      await File(path).writeAsBytes(bytes);
      final id = await repo.insertDocument(DocumentsCompanion.insert(
        uuid: 'docx-uuid',
        format: DocFormat.docx,
        originalName: 'probe.docx',
        title: 'probe',
        storedPath: path,
        sizeBytes: bytes.length,
        sha256: 'docx-sha-probe',
      ));
      doc = (await repo.byId(id))!;
    });

    tearDown(() => db.close());

    test('converts with real page geometry and caches the result', () async {
      final first = await DocxPdfCache.ensure(doc);
      expect(first, AppPaths.docxPdfPath('docx-uuid'));
      final bytes = await File(first).readAsBytes();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final latin = String.fromCharCodes(bytes);
      expect(latin, contains('MediaBox'));
      // Letter page is 612×792 pt — the geometry the old flowing viewer lost.
      expect(latin, contains('612'));
      final again = await DocxPdfCache.ensure(doc);
      expect(again, first);
    });
  });

  group('re-import after delete', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late ImportService importer;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      );
      addTearDown(container.dispose);
      repo = LibraryRepository(db);
      importer = ImportService(repo, MetadataService());
    });

    tearDown(() => db.close());

    test('revives the soft-deleted row instead of colliding', () async {
      final bytes = Uint8List.fromList(utf8.encode('revive me\n'));
      final first = await importer.importBytes({'revive.txt': bytes});
      expect(first.added, 1);
      var docs = await repo.watchLibrary(const LibraryQuery()).first;
      final original = docs.single;
      await repo.deleteDocument(original.id);
      expect(await repo.watchLibrary(const LibraryQuery()).first, isEmpty);

      final second = await importer.importBytes({'revive.txt': bytes});
      expect(second.added, 1, reason: 'must not throw a UNIQUE violation');
      docs = await repo.watchLibrary(const LibraryQuery()).first;
      expect(docs.single.id, original.id);
      expect(docs.single.uuid, original.uuid);
      expect(docs.single.deletedAt, isNull);
    });
  });

  group('collection / tag tombstones', () {
    late AppDatabase db;
    late LibraryRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepository(db);
    });
    tearDown(() => db.close());

    test('deleted collections disappear and are revived by name', () async {
      final id = await repo.createCollection('Favourites');
      await repo.deleteCollection(id);
      expect(await repo.watchCollections().first, isEmpty);

      final revived = await repo.createCollection('Favourites');
      expect(revived, id);
      final live = await repo.watchCollections().first;
      expect(live.single.name, 'Favourites');
    });

    test('deleted tags disappear and are revived by name', () async {
      final id = await repo.createTag('sci-fi');
      await repo.deleteTag(id);
      expect(await repo.watchTags().first, isEmpty);

      final revived = await repo.createTag('sci-fi');
      expect(revived, id);
      expect((await repo.watchTags().first).single.name, 'sci-fi');
    });

    test('manifest accepts legacy bare-string groups', () {
      final manifest = SyncManifest.fromJson({
        'version': 2,
        'collections': ['A', 'B'],
        'tags': ['x'],
      });
      expect(manifest.collections.map((c) => c.name), ['A', 'B']);
      expect(manifest.tags.single.name, 'x');
      expect(manifest.collections.first.deletedAt, isNull);
    });
  });

  group('FB2 decoding', () {
    test('windows-1251 bodies become valid UTF-8 EPUBs', () {
      // "Привет" in cp1251.
      final cyrillic = [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2];
      final head = utf8.encode('<?xml version="1.0" encoding="windows-1251"?>'
          '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
          '<description><title-info><book-title>');
      final tail = utf8.encode('</book-title></title-info></description>'
          '<body><section><p>');
      final end = utf8.encode('</p></section></body></FictionBook>');
      final fb2 = Uint8List.fromList([...head, ...cyrillic, ...tail,
          ...cyrillic, ...end]);

      final epub = fb2ToEpub(fb2);
      final archive = ZipDecoder().decodeBytes(epub);
      final html = archive.files
          .where((f) => f.name.endsWith('.xhtml') || f.name.endsWith('.html'))
          .map((f) => utf8.decode(f.content as List<int>))
          .join();
      expect(html, contains('Привет'));
    });
  });

  group('BookServer token', () {
    setUp(() async {
      await Directory(AppPaths.booksDir.path).create(recursive: true);
      await File('${AppPaths.booksDir.path}/probe.txt')
          .writeAsString('probe body');
      await BookServer.stop();
    });
    tearDown(() => BookServer.stop());

    Future<int> status(String path) async {
      final client = HttpClient();
      final port = await BookServer.ensureRunning();
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final res = await req.close();
      await res.drain<void>();
      client.close();
      return res.statusCode;
    }

    test('rejects missing/bad tokens and serves valid ones', () async {
      expect(await status('/files/probe.txt'), 404);
      expect(await status('/files/probe.txt?t=wrong'), 404);
      expect(await status('/files/probe.txt?t=${BookServer.token}'), 200);
    });
  });
}
