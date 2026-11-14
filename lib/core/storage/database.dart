import 'package:drift/drift.dart';

import '../../core/format/doc_format.dart';
import '../../features/reader/domain/annotations.dart';
import '../../features/reader/domain/viewer_prefs.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
// Core library documents
// ---------------------------------------------------------------------------

class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();

  TextColumn get format => textEnum<DocFormat>()();
  TextColumn get originalName => text()();

  TextColumn get title => text()();
  TextColumn get author => text().nullable()();

  TextColumn get storedPath => text()();
  TextColumn get coverPath => text().nullable()();

  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text().unique()();
  IntColumn get pageCount => integer().nullable()();

  BoolColumn get isFavourite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Last local metadata mutation (title/author/favourite/delete). Null on
  /// rows created before v5 — treated as "oldest" in last-writer-wins
  /// comparisons during WebDAV sync.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// 0 = body text not yet pulled into document_fts (background indexer);
  /// 1 = done (regardless of whether any extractable body existed).
  IntColumn get textIndexed => integer().withDefault(const Constant(0))();
}

// ---------------------------------------------------------------------------
// Collections & tags
// ---------------------------------------------------------------------------

class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
}

class DocumentCollections extends Table {
  IntColumn get documentId => integer().references(Documents, #id)();
  IntColumn get collectionId => integer().references(Collections, #id)();

  @override
  Set<Column> get primaryKey => {documentId, collectionId};
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
}

class DocumentTags extends Table {
  IntColumn get documentId => integer().references(Documents, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {documentId, tagId};
}

/// One row per document: reading position + viewer presentation prefs.
class ReadingPositions extends Table {
  IntColumn get documentId => integer().unique().references(Documents, #id)();
  IntColumn get pageNumber => integer()();

  /// Reflow readers: 0..1 document fraction (page grids don't apply).
  RealColumn get progress => real().nullable()();

  /// Reflow readers: opaque relocator string (EPUB CFI etc.) for exact resume.
  TextColumn get location => text().nullable()();

  TextColumn get fitMode => textEnum<ViewerFitMode>()();
  TextColumn get colorMode => textEnum<ViewerColorMode>()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

// ---------------------------------------------------------------------------
// Annotations (highlights / notes / bookmarks)
// ---------------------------------------------------------------------------

class Annotations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  IntColumn get documentId => integer().references(Documents, #id)();
  TextColumn get kind => textEnum<AnnotationKind>()();

  /// Renderer-specific anchor JSON (see [AnnotationAnchor]).
  TextColumn get anchor => text()();

  /// Quoted text the annotation covers (null for bookmarks).
  TextColumn get excerpt => text().nullable()();

  /// User note attached to the annotation (highlights may carry one).
  TextColumn get note => text().nullable()();

  /// Palette key from [annotationPalette] (highlights only).
  TextColumn get color => text().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  /// Last local annotation mutation — last-writer-wins during sync.
  /// Null on rows created before v6 = oldest.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

/// FTS5 index of the library: one row per non-deleted document, [rowid]
/// aligned with `documents.id`. `body` holds the extracted full text (may
/// stay empty for formats we do not extract). Kept in sync by
/// [LibraryRepository] writes plus the background text indexer.
const ftsCreateSql =
    'CREATE VIRTUAL TABLE IF NOT EXISTS document_fts '
    'USING fts5(title, author, body)';

/// Initial backfill on first creation/upgrade to v4.
const ftsBackfillSql =
    "INSERT INTO document_fts(rowid, title, author, body) "
    "SELECT id, title, COALESCE(author, ''), '' FROM documents "
    'WHERE deleted_at IS NULL';

@DriftDatabase(tables: [
  Documents, Collections, DocumentCollections, Tags, DocumentTags,
  ReadingPositions, Annotations,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // FTS5 is available: sqlite3_flutter_libs ships a full SQLite build.
          await customStatement(ftsCreateSql);
          await customStatement(ftsBackfillSql);
        },
        onUpgrade: (m, from, to) async {
          // addColumn re-run on a partially upgraded DB throws on a duplicate
          // column; guard each ALTER with a PRAGMA check instead.
          Future<void> addColumnIfMissing(
              TableInfo table, GeneratedColumn column) async {
            final names = await customSelect(
                    'PRAGMA table_info(${table.actualTableName})')
                .map((row) => row.read<String>('name'))
                .get();
            if (!names.contains(column.name)) {
              await m.addColumn(table, column);
            }
          }

          if (from < 2) {
            await m.createTable(readingPositions);
          }
          if (from < 3) {
            await addColumnIfMissing(
                readingPositions, readingPositions.progress);
            await addColumnIfMissing(readingPositions, readingPositions.location);
          }
          if (from < 4) {
            await addColumnIfMissing(documents, documents.textIndexed);
            await customStatement(ftsCreateSql);
            await customStatement(ftsBackfillSql);
          }
          if (from < 5) {
            // Nullable column: safe ALTER ADD COLUMN, legacy rows stay NULL
            // (= oldest in sync LWW comparisons until next mutation).
            await addColumnIfMissing(documents, documents.updatedAt);
          }
          if (from < 6) {
            await m.createTable(annotations);
          }
        },
      );
}
