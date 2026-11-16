import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../app/router.dart';
import '../../../core/format/doc_format.dart';
import '../../../core/storage/database.dart';
import '../../dictionary/data/battery_seed_dict.dart';
import '../domain/library_query.dart';
import 'import_service.dart';
import '../presentation/providers.dart';

/// Battery-build-only seeding: bundled/generated books for on-device runs.
///
/// Everything here is reached solely through the `batteryHook` (const-false)
/// branch in the library screen, so release builds tree-shake it away.
class BatterySeeder {
  BatterySeeder(this._ref);

  final WidgetRef _ref;

  /// Imports the standard seed set once, then returns the document the
  /// battery should auto-open (or null when this boot should stay on the
  /// library grid).
  Future<Document?> seed() async {
    // Idempotent across boots: the generated seeds embed zip timestamps, so
    // their sha256 differs per boot — skip when any previous generation is
    // already in the library (prevents boot-2 duplicates during sync runs;
    // partial earlier imports may lack mini.pdf but carry battery.* seeds).
    final already = await _ref.read(appDatabaseProvider).customSelect(
          "SELECT COUNT(*) c FROM documents WHERE original_name = 'mini.pdf'"
          " OR original_name LIKE 'battery.%'",
        ).getSingle();
    if ((already.data['c'] as int?) != 0) return null;
    final data = await rootBundle.load('assets/battery/mini.pdf');
    final summary = await _ref.read(importServiceProvider).importBytes(
          {
            'mini.pdf': data.buffer.asUint8List(),
            'battery.epub': makeEpub(),
            'battery.txt': makeTxt(),
            'battery.docx': await makeDocx(),
            'battery.xlsx': makeXlsx(),
            'battery.pptx': makePptx(),
            'battery.odt': makeOdt(),
            'battery.rtf': makeRtf(),
          },
        );
    if (summary.added < 1) return null;
    // Seed a collection so the filter-chip bar has something to render.
    try {
      final repo = _ref.read(libraryRepositoryProvider);
      final colId = await repo.createCollection('Battery set');
      final docs = await repo.watchLibrary(const LibraryQuery()).first;
      for (final d in docs) {
        if (d.originalName == 'mini.pdf' || d.originalName == 'battery.epub') {
          await repo.setDocumentCollections(d.id, {colId});
        }
      }
    } catch (_) {
      // Collection seeding is cosmetic; never fail the battery boot.
    }
    // Big-library battery: inflate with N cheap TXT docs, then stay on the
    // library grid (no reader auto-open) so boot/scroll behavior is visible.
    if (batteryBigLib > 0) {
      await seedBigLibrary();
      return null;
    }
    // Battery runs can pin a specific seed format (DOCVIEW_BATTERY_OPEN).
    // 'none' imports only (library-search batteries); default: office first.
    if (batteryOpenFormat.toLowerCase() == 'none') return null;
    if (batteryDictWord.isNotEmpty) {
      await seedBatteryStarDict();
    }
    final docs = await _ref
        .read(libraryRepositoryProvider)
        .watchLibrary(const LibraryQuery())
        .first;
    final pinned = () {
      switch (batteryOpenFormat.toLowerCase()) {
        case 'xlsx':
          return DocFormat.xlsx;
        case 'pptx':
          return DocFormat.pptx;
        case 'odt':
          return DocFormat.odt;
        case 'rtf':
          return DocFormat.rtf;
        case 'pdf':
          return DocFormat.pdf;
        case 'epub':
          return DocFormat.epub;
        case 'docx':
          return DocFormat.docx;
        default:
          return null;
      }
    }();
    const priority = [
      DocFormat.docx,
      DocFormat.xlsx,
      DocFormat.pptx,
      DocFormat.odt,
      DocFormat.rtf,
      DocFormat.epub,
      DocFormat.txt,
    ];
    Document? doc;
    for (final fmt in [?pinned, ...priority]) {
      for (final d in docs) {
        if (d.format == fmt) {
          doc = d;
          break;
        }
      }
      if (doc != null) break;
    }
    return doc ?? (docs.isNotEmpty ? docs.first : null);
  }

  /// Big-library battery seed: `batteryBigLib` small TXT docs in batches of
  /// 20, yielding between batches so boot stays responsive. Names keep the
  /// `battery.*` prefix so the idempotent guard covers re-boots.
  Future<void> seedBigLibrary() async {
    final importer = _ref.read(importServiceProvider);
    final batch = 20;
    for (var base = 0; base < batteryBigLib; base += batch) {
      final count = (batteryBigLib - base).clamp(1, batch);
      final files = <String, Uint8List>{};
      for (var i = 0; i < count; i++) {
        final n = base + i;
        files['battery.biglib$n.txt'] = utf8.encode(
          'Big library probe $n\n\n'
          '${'Sample paragraph for indexing, search and card rendering. ' * 40}',
        );
      }
      await importer.importBytes(files);
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Edge battery: download every file listed in the edge dir's
  /// `_index.txt` once (sha-deduped), then return the next never-opened doc
  /// through the real reader route — each boot advances one doc, so the
  /// script can capture per-file reader behavior (corrupt, empty, huge,
  /// odd formats, encrypted).
  Future<Document?> edgeImport() async {
    try {
      final idx = await http.get(Uri.parse('${batteryEdgeUrl}_index.txt'));
      if (idx.statusCode != 200) {
        debugPrint('[battery] edge index missing: ${idx.statusCode}');
        return null;
      }
      final names = utf8
          .decode(idx.bodyBytes)
          .split('\n')
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty)
          .toList();
      final files = <String, Uint8List>{};
      for (final name in names) {
        final r = await http.get(Uri.parse('$batteryEdgeUrl$name'));
        if (r.statusCode == 200) files[name] = r.bodyBytes;
      }
      if (files.isNotEmpty) {
        await _ref.read(importServiceProvider).importBytes(files);
      }
    } on Object catch (e) {
      debugPrint('[battery] edge import failed: $e');
    }
    try {
      final docs = await _ref
          .read(libraryRepositoryProvider)
          .watchLibrary(const LibraryQuery(sort: LibrarySort.addedAt))
          .first;
      if (docs.isEmpty) return null;
      return docs.firstWhere((d) => d.lastOpenedAt == null,
          orElse: () => docs.first);
    } on Object catch (e) {
      debugPrint('[battery] edge open failed: $e');
      return null;
    }
  }

  // --- generated seed documents ---------------------------------------------

  /// Minimal three-chapter EPUB, built in memory with the archive package.
  static Uint8List makeEpub() {
      final archive = Archive();

    ArchiveFile utf8File(String name, String content,
            {CompressionType compression = CompressionType.deflate}) =>
        ArchiveFile.bytes(name, utf8.encode(content))..compression = compression;

    archive.addFile(utf8File('mimetype', 'application/epub+zip',
        compression: CompressionType.none));
    archive.addFile(utf8File(
        'META-INF/container.xml',
        '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''));

    const chapterNames = ['Wind', 'Harbor', 'Dawn'];
    final manifest = StringBuffer('<item id="nav" properties="nav" '
        'href="nav.xhtml" media-type="application/xhtml+xml"/>');
    final navItems = StringBuffer();
    var chapterIndex = 1;
    for (final name in chapterNames) {
      final body = StringBuffer('<h1>Chapter $name</h1>');
      for (var i = 1; i <= 25; i++) {
        body.write('<p>Paragraph $i of $name. The quick brown fox jumps '
            'over the lazy dog while the calm river folds its silver ribbons '
            'toward the open sea, and every lamp in the harbor keeps a '
            'patient watch until dawn arrives at the break of the tide.</p>');
      }
      final xhtml = '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
          '<title>$name</title></head><body>$body</body></html>';
      archive.addFile(utf8File('OEBPS/ch$chapterIndex.xhtml', xhtml));
      manifest.write('<item id="c$chapterIndex" href="ch$chapterIndex.xhtml" '
          'media-type="application/xhtml+xml"/>');
      navItems.write('<li><a href="ch$chapterIndex.xhtml">Chapter $name</a></li>');
      chapterIndex++;
    }

    archive.addFile(utf8File(
        'OEBPS/nav.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Nav</title>'
        '</head><body><nav epub:type="toc"><ol>$navItems</ol></nav>'
        '</body></html>'));
    archive.addFile(utf8File(
        'OEBPS/content.opf',
        '<?xml version="1.0" encoding="utf-8"?>'
        '<package version="3.0" unique-identifier="uid" '
        'xmlns="http://www.idpf.org/2007/opf">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>Battery EPUB</dc:title>'
        '<dc:language>en</dc:language>'
        '<dc:identifier id="uid">urn:uuid:docview-battery-epub</dc:identifier>'
        '<meta property="dcterms:modified">2026-11-06T00:00:00Z</meta>'
        '</metadata>'
        '<manifest>$manifest</manifest>'
        '<spine><itemref idref="c1"/>'
        '<itemref idref="c2"/><itemref idref="c3"/></spine>'
        '</package>'));

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// A long plain-text document (goes through the TXT→EPUB conversion).
  static Uint8List makeTxt() {
    final buf = StringBuffer();
    for (var ch = 1; ch <= 5; ch++) {
      buf.writeln('Chapter $ch');
      buf.writeln();
      for (var i = 1; i <= 40; i++) {
        buf.writeln('Paragraph $i. Salt air settles on the old breakwater '
            'and the tide keeps its own account of everything that drifts '
            'out with the evening star.');
      }
      buf.writeln();
    }
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  /// Word document, generated with docx_creator (the same package that
  /// powers the native DOCX reader).
  static Future<Uint8List> makeDocx() async {
    final doc = docx()
        .h1('Battery Report')
        .p('This Word file was generated in memory to exercise the '
            'Phase 4 native DOCX reader through the real import pipeline.')
        .bullet(['Paragraphs', 'Lists', 'Tables', 'Images'])
        .table([
          ['Region', 'Q1', 'Q2'],
          ['Harbor', '1,200', '1,850'],
          ['Dawn', '980', '1,420'],
        ])
        .build();
    return Uint8List.fromList(await DocxExporter().exportToBytes(doc));
  }

  /// Spreadsheet, generated with excel_plus (two sheets to exercise tabs,
  /// styled header, frozen first row in the reader).
  static Uint8List makeXlsx() {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Report');
    final report = excel['Report'];
    final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#4472C4'));
    final headers = ['Month', 'Wind', 'Harbor', 'Dawn'];
    for (var c = 0; c < headers.length; c++) {
      report.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
        cellStyle: headerStyle,
      );
    }
    final months = [
      ['January', '12', '18', '9'],
      ['February', '14', '17', '11'],
      ['March', '19', '21', '15'],
      ['April', '22', '24', '18'],
      ['May', '26', '27', '21'],
    ];
    for (var r = 0; r < months.length; r++) {
      for (var c = 0; c < months[r].length; c++) {
        report.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          TextCellValue(months[r][c]),
        );
      }
    }
    final data = excel['Notes'];
    data.updateCell(
      CellIndex.indexByString('A1'),
      TextCellValue('Second sheet checks the tab switcher'),
    );
    return Uint8List.fromList(excel.save()!);
  }

  /// Minimal Open XML presentation: only the slideN.xml parts the Phase 4
  /// extractor reads (no rendering engine is involved).
  static Uint8List makePptx() {
    final archive = Archive();
    String slideXml(String title, List<String> body) {
      final sp =
          '<p:sp><p:txBody><a:p><a:r><a:t>@</a:t></a:r></a:p></p:txBody></p:sp>';
      final parts = StringBuffer(sp.replaceFirst('@', title));
      for (final line in body) {
        parts.write(sp.replaceFirst('@', line));
      }
      return '<?xml version="1.0" encoding="UTF-8"?>'
          '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
          '<p:cSld><p:spTree>$parts</p:spTree></p:cSld></p:sld>';
    }

    void addSlide(int n, String title, List<String> body) {
      archive.addFile(ArchiveFile.bytes(
          'ppt/slides/slide$n.xml', utf8.encode(slideXml(title, body))));
    }

    addSlide(1, 'DocView Battery Deck', ['Phase 4 slide extraction']);
    addSlide(2, 'Second slide', ['Overview list', 'Readable text view']);
    addSlide(3, 'Final slide', ['That is all']);
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// OpenDocument text file (heading + paragraphs, built with archive).
  static Uint8List makeOdt() {
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes(
        'mimetype', const AsciiCodec().encode('application/vnd.oasis.opendocument.text'))..compression = CompressionType.none);
    archive.addFile(ArchiveFile.bytes(
        'content.xml',
        utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body><office:text>
    <text:h>Battery Notes</text:h>
    <text:p>ODT files are Open XML-style packages; the reader unzips content.xml and extracts the paragraphs directly.</text:p>
    <text:p>Second paragraph to have something to scroll through on the tablet.</text:p>
  </office:text></office:body>
</office:document-content>''')));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Rich text file with an escape/unicode mix (the Phase 4 RTF extractor).
  static Uint8List makeRtf() => Uint8List.fromList(
        utf8.encode(
            r"{\rtf1\ansi Battery Rich Text\'e9\par Second paragraph with "
            r'{\*\generator ignored metadata} plain body text \par Done.'),
      );
}
