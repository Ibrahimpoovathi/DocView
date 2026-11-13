import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/database.dart';
import '../domain/annotations.dart';

/// CRUD for per-document annotations (highlights, notes, bookmarks).
/// Every mutation stamps [Annotations.updatedAt] for sync LWW; deletes are
/// soft (tombstones drive the WebDAV merge).
class AnnotationsRepository {
  AnnotationsRepository(this._db);

  final AppDatabase _db;

  /// Live annotations for a document (oldest first), soft-deleted excluded.
  Stream<List<Annotation>> watchForDoc(int docId) =>
      (_db.select(_db.annotations)
            ..where((a) => a.documentId.equals(docId) & a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
          .watch();

  /// One-shot list for the sync engine and export.
  Future<List<Annotation>> listForDoc(int docId) =>
      (_db.select(_db.annotations)
            ..where((a) => a.documentId.equals(docId) & a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
          .get();

  Future<Annotation?> byUuid(String uuid) =>
      (_db.select(_db.annotations)..where((a) => a.uuid.equals(uuid)))
          .getSingleOrNull();

  Future<Annotation> create(
    int docId, {
    required AnnotationKind kind,
    required AnnotationAnchor anchor,
    String? excerpt,
    String? note,
    String? color,
    DateTime? createdAt,
  }) async {
    final now = DateTime.now();
    final stamp = createdAt ?? now;
    await _db.into(_db.annotations).insert(AnnotationsCompanion.insert(
          uuid: newAnnotationUuid(),
          documentId: docId,
          kind: kind,
          anchor: jsonEncode(anchor.toJson()),
          excerpt: Value(excerpt == null || excerpt.isEmpty ? null : excerpt),
          note: Value(note == null || note.isEmpty ? null : note),
          color: Value(color),
          createdAt: Value(stamp),
          updatedAt: Value(now),
        ));
    // uuid is generated above; refetch is the cheapest drift-safe path.
    return (_db.select(_db.annotations)
          ..where((a) => a.documentId.equals(docId) & a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.id)])
          ..limit(1))
        .getSingle();
  }

  Future<void> update(
    int id, {
    String? note,
    String? color,
  }) async {
    await (_db.update(_db.annotations)..where((a) => a.id.equals(id)))
        .write(AnnotationsCompanion(
      note: note == null
          ? const Value.absent()
          : Value(note.isEmpty ? null : note),
      color: color == null ? const Value.absent() : Value(color),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Tombstone: keeps the row for the sync merge, hides it from readers.
  Future<void> softDelete(int id) async {
    await (_db.update(_db.annotations)..where((a) => a.id.equals(id)))
        .write(AnnotationsCompanion(
      deletedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Merge an annotation coming from the sync manifest by uuid.
  ///
  /// LWW: the newer [updatedAt] wins; ties are deletion-dominant (Drift
  /// stores DateTime at second precision, so sub-second mutations tie —
  /// a device must never resurrect its own just-deleted annotation).
  Future<void> upsertRemote(AnnotationsCompanion entry) async {
    final uuid = entry.uuid.value;
    final local = await byUuid(uuid);
    if (local == null) {
      await _db.into(_db.annotations).insert(entry);
      return;
    }
    final remoteUpdated = entry.updatedAt.present
        ? entry.updatedAt.value
        : local.updatedAt;
    final remoteDeleted =
        entry.deletedAt.present ? entry.deletedAt.value : local.deletedAt;
    final localNewer = local.updatedAt != null &&
        (remoteUpdated == null ||
            local.updatedAt!.isAfter(remoteUpdated));
    if (localNewer) return;
    final tie = local.updatedAt != null &&
        remoteUpdated != null &&
        !local.updatedAt!.isAfter(remoteUpdated) &&
        !remoteUpdated.isAfter(local.updatedAt!);
    if (tie) {
      // Deletion-dominant: a tie (same-second mutation) with either side
      // tombstoned keeps the tombstone — a device must never resurrect its
      // own just-deleted annotation from its own earlier manifest echo.
      if (remoteDeleted != null || local.deletedAt != null) {
        await (_db.update(_db.annotations)
              ..where((a) => a.id.equals(local.id)))
            .write(AnnotationsCompanion(
          updatedAt: Value(remoteUpdated),
          deletedAt: Value(remoteDeleted ?? local.deletedAt),
        ));
      }
      return;
    }

    // Keep drift's own id/uuid; take remote content.
    await (_db.update(_db.annotations)..where((a) => a.id.equals(local.id)))
        .write(AnnotationsCompanion(
      documentId: entry.documentId.present
          ? entry.documentId
          : Value(local.documentId),
      kind: entry.kind.present ? entry.kind : Value(local.kind),
      anchor: entry.anchor.present ? entry.anchor : Value(local.anchor),
      excerpt:
          entry.excerpt.present ? entry.excerpt : Value(local.excerpt),
      note: entry.note.present ? entry.note : Value(local.note),
      color: entry.color.present ? entry.color : Value(local.color),
      createdAt:
          entry.createdAt.present ? entry.createdAt : Value(local.createdAt),
      updatedAt: Value(remoteUpdated ?? local.updatedAt),
      deletedAt: Value(remoteDeleted),
    ));
  }
}
