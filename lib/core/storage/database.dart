import 'package:drift/drift.dart';

import '../../core/format/doc_format.dart';

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

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Documents, Collections, DocumentCollections, Tags, DocumentTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
