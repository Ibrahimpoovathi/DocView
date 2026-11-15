import 'package:docview/core/storage/database.dart';

/// Typed model over the remote `DocView/manifest.json`.
///
/// Everything is keyed by content identity (`sha256` for documents, `name`
/// for collections/tags) so the manifest reconciles identically on any
/// device regardless of locally generated ids/uuids.
class SyncManifest {
  static const int version = 3;

  final List<SyncDoc> documents;
  final List<SyncPosition> positions;
  final List<SyncAnnotation> annotations;
  final List<SyncName> collections;
  final List<SyncName> tags;
  final List<SyncLink> documentCollections;
  final List<SyncLink> documentTags;
  final DateTime? syncedAt;

  const SyncManifest({
    required this.documents,
    required this.positions,
    this.annotations = const [],
    required this.collections,
    required this.tags,
    required this.documentCollections,
    required this.documentTags,
    this.syncedAt,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'syncedAt': syncedAt?.toIso8601String(),
        'documents': documents.map((d) => d.toJson()).toList(),
        'positions': positions.map((p) => p.toJson()).toList(),
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'collections': collections.map((c) => c.toJson()).toList(),
        'tags': tags.map((t) => t.toJson()).toList(),
        'documentCollections': documentCollections.map((l) => l.toJson()).toList(),
        'documentTags': documentTags.map((l) => l.toJson()).toList(),
      };

  static SyncManifest fromJson(Map<String, dynamic> json) {
    final docs = (json['documents'] as List<dynamic>? ?? const [])
        .map((e) => SyncDoc.fromJson(e as Map<String, dynamic>))
        .toList();
    final positions = (json['positions'] as List<dynamic>? ?? const [])
        .map((e) => SyncPosition.fromJson(e as Map<String, dynamic>))
        .toList();
    // v1 manifests carry no annotations.
    final annotations = (json['annotations'] as List<dynamic>? ?? const [])
        .map((e) => SyncAnnotation.fromJson(e as Map<String, dynamic>))
        .toList();
    // v3 stores {name, updatedAt, deletedAt}; v1/v2 stored bare names.
    final collections = (json['collections'] as List<dynamic>? ?? const [])
        .map(SyncName.fromJson)
        .toList();
    final tags = (json['tags'] as List<dynamic>? ?? const [])
        .map(SyncName.fromJson)
        .toList();
    final docCollections = (json['documentCollections'] as List<dynamic>? ?? const [])
        .map((e) => SyncLink.fromJson(e as Map<String, dynamic>))
        .toList();
    final docTags = (json['documentTags'] as List<dynamic>? ?? const [])
        .map((e) => SyncLink.fromJson(e as Map<String, dynamic>))
        .toList();
    final syncedAtRaw = json['syncedAt'] as String?;
    return SyncManifest(
      documents: docs,
      positions: positions,
      annotations: annotations,
      collections: collections,
      tags: tags,
      documentCollections: docCollections,
      documentTags: docTags,
      syncedAt: syncedAtRaw == null ? null : DateTime.tryParse(syncedAtRaw),
    );
  }
}

/// A named group (collection or tag) with its sync timestamps.
class SyncName {
  final String name;
  final DateTime? updatedAt;

  /// Non-null means the group was deleted locally; deletions propagate.
  final DateTime? deletedAt;

  const SyncName({
    required this.name,
    this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };

  /// Accepts both the v3 object form and the legacy bare-string form.
  static SyncName fromJson(Object? raw) {
    if (raw is String) return SyncName(name: raw);
    if (raw is Map) {
      final map = raw.cast<String, Object?>();
      return SyncName(
        name: (map['name'] as String?) ?? '',
        updatedAt: DateTime.tryParse((map['updatedAt'] as String?) ?? ''),
        deletedAt: DateTime.tryParse((map['deletedAt'] as String?) ?? ''),
      );
    }
    return const SyncName(name: '');
  }

  /// The effective mutation instant used for last-writer-wins.
  DateTime? get mutation => deletedAt ?? updatedAt;
}

/// One annotation in the manifest, keyed by uuid + document sha256.
class SyncAnnotation {
  final String uuid;
  final String sha256;
  final String kind;
  final String anchor;

  /// Raw anchor JSON (opaque to the sync layer).
  final String? excerpt;
  final String? note;
  final String? color;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const SyncAnnotation({
    required this.uuid,
    required this.sha256,
    required this.kind,
    required this.anchor,
    required this.excerpt,
    required this.note,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory SyncAnnotation.fromRow(String sha256, Annotation row) =>
      SyncAnnotation(
        uuid: row.uuid,
        sha256: sha256,
        kind: row.kind.name,
        anchor: row.anchor,
        excerpt: row.excerpt,
        note: row.note,
        color: row.color,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'sha256': sha256,
        'kind': kind,
        'anchor': anchor,
        'excerpt': excerpt,
        'note': note,
        'color': color,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  static SyncAnnotation fromJson(Map<String, dynamic> json) => SyncAnnotation(
        uuid: json['uuid'] as String,
        sha256: json['sha256'] as String,
        kind: json['kind'] as String? ?? 'highlight',
        anchor: json['anchor'] as String? ?? '{}',
        excerpt: json['excerpt'] as String?,
        note: json['note'] as String?,
        color: json['color'] as String?,
        createdAt: _dt(json['createdAt']),
        updatedAt: _dt(json['updatedAt']),
        deletedAt: _dt(json['deletedAt']),
      );

  static DateTime? _dt(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}

/// One document in the manifest. `sha256` is the cross-device identity;
/// `uuid` is carried along so imports can adopt a stable remote id.
class SyncDoc {
  final String sha256;
  final String uuid;
  final String title;
  final String? author;
  final String format;
  final int? pageCount;
  final bool favourite;
  final DateTime? addedAt;
  final DateTime? lastOpenedAt;
  final DateTime? deletedAt;
  final DateTime? updatedAt;

  const SyncDoc({
    required this.sha256,
    required this.uuid,
    required this.title,
    required this.author,
    required this.format,
    required this.pageCount,
    required this.favourite,
    this.addedAt,
    this.lastOpenedAt,
    this.deletedAt,
    this.updatedAt,
  });

  factory SyncDoc.fromRow(Document row) => SyncDoc(
        sha256: row.sha256,
        uuid: row.uuid,
        title: row.title,
        author: row.author,
        format: row.format.name,
        pageCount: row.pageCount,
        favourite: row.isFavourite,
        addedAt: row.addedAt,
        lastOpenedAt: row.lastOpenedAt,
        deletedAt: row.deletedAt,
        updatedAt: row.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'sha256': sha256,
        'uuid': uuid,
        'title': title,
        'author': author,
        'format': format,
        'pageCount': pageCount,
        'favourite': favourite,
        'addedAt': addedAt?.toIso8601String(),
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static SyncDoc fromJson(Map<String, dynamic> json) => SyncDoc(
        sha256: json['sha256'] as String,
        uuid: json['uuid'] as String,
        title: json['title'] as String? ?? '',
        author: json['author'] as String?,
        format: json['format'] as String? ?? 'pdf',
        pageCount: json['pageCount'] as int?,
        favourite: json['favourite'] as bool? ?? false,
        addedAt: _dt(json['addedAt']),
        lastOpenedAt: _dt(json['lastOpenedAt']),
        deletedAt: _dt(json['deletedAt']),
        updatedAt: _dt(json['updatedAt']),
      );

  static DateTime? _dt(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}

class SyncPosition {
  final String sha256;
  final int lastPage;
  final double? fraction;
  final String? location;
  final DateTime? updatedAt;
  final String? fitMode;
  final String? colorMode;

  const SyncPosition({
    required this.sha256,
    required this.lastPage,
    required this.fraction,
    this.location,
    this.updatedAt,
    this.fitMode,
    this.colorMode,
  });

  factory SyncPosition.fromRow(Document doc, ReadingPosition row) => SyncPosition(
        sha256: doc.sha256,
        lastPage: row.pageNumber,
        fraction: row.progress,
        location: row.location,
        updatedAt: row.updatedAt,
        fitMode: row.fitMode.name,
        colorMode: row.colorMode.name,
      );

  Map<String, dynamic> toJson() => {
        'sha256': sha256,
        'lastPage': lastPage,
        'fraction': fraction,
        'location': location,
        'updatedAt': updatedAt?.toIso8601String(),
        'fitMode': fitMode,
        'colorMode': colorMode,
      };

  static SyncPosition fromJson(Map<String, dynamic> json) => SyncPosition(
        sha256: json['sha256'] as String,
        lastPage: json['lastPage'] as int? ?? 1,
        fraction: (json['fraction'] as num?)?.toDouble(),
        location: json['location'] as String?,
        updatedAt: _dt(json['updatedAt']),
        fitMode: json['fitMode'] as String?,
        colorMode: json['colorMode'] as String?,
      );

  static DateTime? _dt(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  /// LWW: true when [this] should win over [other].
  bool newerThan(SyncPosition other) {
    final a = updatedAt;
    final b = other.updatedAt;
    if (a == null) return false;
    if (b == null) return true;
    return a.isAfter(b);
  }
}

/// A document↔collection/tag link, keyed by sha256 + name.
class SyncLink {
  final String sha256;
  final String name;

  const SyncLink({required this.sha256, required this.name});

  Map<String, dynamic> toJson() => {'sha256': sha256, 'name': name};

  static SyncLink fromJson(Map<String, dynamic> json) => SyncLink(
        sha256: json['sha256'] as String,
        name: json['name'] as String,
      );
}
