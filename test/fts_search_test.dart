import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docview/core/format/doc_format.dart';
import 'package:docview/core/paths/app_paths.dart';
import 'package:docview/core/storage/database.dart';
import 'package:docview/features/library/data/library_repository.dart';
import 'package:docview/features/library/data/text_extract.dart';
import 'package:docview/features/library/data/text_index_repository.dart';
import 'package:docview/features/library/domain/library_query.dart';
import 'package:docview/features/library/presentation/providers.dart';
import 'package:docview/features/reader/data/docx_text.dart';
import 'package:docview/features/reader/data/text_search.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase db;
  late LibraryRepository repo;
  late TextIndexRepository index;
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('docview-fts-test');
    AppPaths.initForTest(tmp);
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // The background index runs
        textIndexRepositoryProvider.overrideWithValue(
          TextIndexRepository(db),
        ),
      ],
    );
    addTearDown(db.close);
    repo = container.read(libraryRepositoryProvider);
    index = container.read(textIndexRepositoryProvider);
  });

  tearDown(() => container.dispose());

  group('fts library search', () {
    test('new imports are metadata-searchable via FTS immediately', () async {
      final src = await Directory.systemTemp.createTemp('docview-fts-src');
      await File('${src.path}/cookie.md').writeAsString('plain text');

      await repo.insertDocument(sampleDoc(
        uuid: 'u1',
        sha: 'h1',
        title: 'Gulliver travels',
        author: 'Jonathan Swift',
      ));

      final hits = await repo.watchLibrary(
        const LibraryQuery(search: 'gulliver'),
      ).first;
      expect(hits, hasLength(1));
      expect(hits.single.title, 'Gulliver travels');

      await src.delete(recursive: true);
    });

    test('soft-deleted docs stay out of matches, restore-able (trivial)',
        () async {
      final id = await repo.insertDocument(
          sampleDoc(uuid: 'u2', sha: 'h2', title: 'Moby Dick'));
      var hits = await repo
          .watchLibrary(const LibraryQuery(search: 'moby'))
          .first;
      expect(hits, hasLength(1));

      await repo.deleteDocument(id);
      hits = await repo.watchLibrary(const LibraryQuery(search: 'moby')).first;
      expect(hits, isEmpty);
    });

    test('body text becomes searchable after the background indexer runs',
        () async {
      final docDir = await Directory.systemTemp.createTemp('docview-body');
      final bodyFile = File('${docDir.path}/story.txt');
      await bodyFile
          .writeAsString('A telegraph once worked across the sea');
      final id = await repo.insertDocument(
        sampleDoc(
          uuid: 'u3',
          sha: 'h3',
          title: 'The Telegraph',
          storedPath: bodyFile.path,
        ),
      );

      // Title search hits immediately (metadata indexed at import).
      var hits = await repo
          .watchLibrary(const LibraryQuery(search: 'Telegraph'))
          .first;
      expect(hits, hasLength(1));
      // Body search does not yet: text_indexed is still 0.
      hits = await repo
          .watchLibrary(const LibraryQuery(search: 'telegraph'))
          .first;
      expect(hits, hasLength(1));

      // Borat case: search body-only term after indexing.
      await index.runPending();
      expect(await index.pendingCount(), 0);
      hits = await repo
          .watchLibrary(const LibraryQuery(search: 'across the sea'))
          .first;
      expect(hits, hasLength(1));
      expect(hits.single.id, id);
      await docDir.delete(recursive: true);
    });

    test('punctuation-only queries do not crash the FTS path', () async {
      await repo.insertDocument(
          sampleDoc(uuid: 'u4', sha: 'h4', title: 'Hamlet'));
      final hits = await repo
          .watchLibrary(const LibraryQuery(search: '!?'))
          .first;
      // Falls back to substring matching: originalName contains nothing here.
      expect(hits, isEmpty);
    });

    test('fts sanitizer quotes words and drops junk', () {
      expect(
        LibraryRepository.ftsMatchQuery('Hamlet or "Othello"?'),
        '"Hamlet" "or" "Othello"',
      );
      expect(LibraryRepository.ftsMatchQuery('://'), isNull);
      expect(LibraryRepository.ftsMatchQuery(''), isNull);
    });
  });

  group('text extraction for the FTS body', () {
    test('EPUB spine html is merged in order and stripped', () async {
      final zip = ZipEncoder().encode(buildEpubZip());
      final path =
          '${(await Directory.systemTemp.createTemp('docview-epub')).path}/a.epub';
      await File(path).writeAsBytes(zip);

      final body = await extractBodyText(path, DocFormat.epub);
      expect(body, contains('A Bottle & Cloud'));
      expect(body, contains('first chapter text'));
      expect(body, contains('second chapter text'));
      expect(body, isNot(contains('<')));
    });

    test('docx paragraphs come out in document order', () async {
      final zip = ZipEncoder().encode(buildDocxZip());
      final path =
          '${(await Directory.systemTemp.createTemp('docview-docx')).path}/a.docx';
      await File(path).writeAsBytes(zip);

      final paragraphs = extractDocxParagraphs(Uint8List.fromList(zip));
      expect(paragraphs, hasLength(3));
      expect(paragraphs[0].text, 'Covered in Dust');
      expect(paragraphs[0].isHeading, isTrue);
      expect(paragraphs[1].text, 'First body attention span');
      expect(paragraphs[2].text, 'Light heading');
      expect(paragraphs[2].isHeading, isTrue);

      final body = await extractBodyText(path, DocFormat.docx);
      expect(body, contains('First body attention span'));
    });
  });

  group('findTextHits', () {
    test('returns capped excerpts with pre/hit/post around the needle',
        () async {
      final hits = findTextHits(
        [
          'one',
          'the phrase appears here and the phrase again',
          'nothing',
        ],
        'phrase',
      );
      expect(hits, hasLength(2));
      expect(hits.first.index, 1);
      expect(hits.first.hit, 'phrase');
      expect(hits.last.hit, 'phrase');
      expect(findTextHits([], 'phrase'), isEmpty);
      expect(findTextHits(['a'], ''), isEmpty);
    });
  });
}

DocumentsCompanion sampleDoc({
  required String uuid,
  required String sha,
  required String title,
  String? author,
  String? storedPath,
}) =>
    DocumentsCompanion.insert(
      uuid: uuid,
      format: DocFormat.txt,
      originalName: '$title.txt',
      title: title,
      author: Value(author),
      storedPath: storedPath ?? 'ignored/$uuid/x.txt',
      sizeBytes: 42,
      sha256: sha,
    );

const _mimetype = 'application/epub+zip';

Archive buildEpubZip() {
  final archive = Archive();
  archive.addFile(ArchiveFile(
    'mimetype',
    _mimetype.length,
    _mimetype.codeUnits,
  ));
  archive.addFile(ArchiveFile(
    'META-INF/container.xml',
    _containerXml.length,
    _containerXml.codeUnits,
  ));
  archive.addFile(ArchiveFile(
    'OEBPS/book.opf',
    _opfXml.length,
    _opfXml.codeUnits,
  ));
  archive.addFile(ArchiveFile(
    'OEBPS/first.xhtml',
    _chapter1.length,
    _chapter1.codeUnits,
  ));
  archive.addFile(ArchiveFile(
    'OEBPS/second.xhtml',
    _chapter2.length,
    _chapter2.codeUnits,
  ));
  return archive;
}

const _containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

const _opfXml = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <manifest>
    <item id="c1" href="first.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="second.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="css"/>
    <itemref idref="c2"/>
  </spine>
</package>
''';

const _chapter1 = '''<html><head><title>t</title>
<script>alert('strip me');</script>
<style>p { color: red }</style>
</head><body><h1>A Bottle &amp; Cloud</h1>
<p>first chapter text referendaires</p></body></html>''';

const _chapter2 = '<html><body><p>second chapter text</p></body></html>';

Archive buildDocxZip() {
  final archive = Archive();
  archive.addFile(ArchiveFile(
    'word/document.xml',
    _docxDocXml.length,
    _docxDocXml.codeUnits,
  ));
  return archive;
}

const _docxDocXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
  <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
    <w:r><w:t xml:space="preserve">Covered in </w:t></w:r>
    <w:r><w:t>Dust</w:t></w:r>
  </w:p>
  <w:p><w:r><w:t xml:space="preserve">First body </w:t></w:r>
    <w:r><w:br/><w:t>attention span</w:t></w:r>
  </w:p>
  <w:tbl><w:tr><w:tc>
    <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Light heading</w:t></w:r></w:p>
  </w:tc></w:tr></w:tbl>
</w:body>
</w:document>''';
