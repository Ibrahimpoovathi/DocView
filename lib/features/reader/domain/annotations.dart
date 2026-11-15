import 'dart:convert';

/// Annotation kinds stored per document.
enum AnnotationKind { highlight, note, bookmark }

/// Fixed highlight palette (user-approved; no free-form picker).
const annotationPalette = ['yellow', 'green', 'blue', 'red', 'magenta'];

/// Renderer-specific position anchor, serialized to JSON in the DB.
///
/// Reflow readers anchor to a relocator string (EPUB CFI etc.):
/// `{"cfi": "epubcfi(...)"}`.
/// PDF anchors to a char range on a page (1-based page number, char
/// indices into the page text produced by pdfrx's deterministic
/// extraction): `{"page": 3, "start": 10, "end": 42}`.
/// A bookmark usually carries both forms so either reader can restore it.
class AnnotationAnchor {
  const AnnotationAnchor({this.cfi, this.page, this.start, this.end});

  factory AnnotationAnchor.fromJson(Map<String, Object?> json) =>
      AnnotationAnchor(
        cfi: json['cfi'] is String ? json['cfi'] as String : null,
        page: (json['page'] as num?)?.toInt(),
        start: (json['start'] as num?)?.toInt(),
        end: (json['end'] as num?)?.toInt(),
      );

  final String? cfi;

  /// 1-based PDF page.
  final int? page;

  /// Inclusive char-index range into the page text (PDF).
  final int? start;
  final int? end;

  Map<String, Object?> toJson() => {
        if (cfi != null) 'cfi': cfi,
        if (page != null) 'page': page,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
      };
}

/// Stable-enough identifier for annotations: timestamp base-36 + a
/// short random tail (no sha here — annotations are not content files).
String newAnnotationUuid() {
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final tail =
      DateTime.now().microsecondsSinceEpoch.toRadixString(36).substring(0, 6);
  return '$ts-$tail';
}

/// Tolerant parse of a stored anchor. A single malformed row (older build,
/// manual edit, interrupted sync) must never break the reader or the list.
/// Results are memoised by raw JSON (anchors are immutable per row).
final Map<String, AnnotationAnchor?> _anchorCache = {};

AnnotationAnchor? tryParseAnchor(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (_anchorCache.containsKey(raw)) return _anchorCache[raw];
  AnnotationAnchor? parsed;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      parsed = AnnotationAnchor.fromJson(decoded.cast<String, Object?>());
    }
  } on Object {
    parsed = null;
  }
  if (_anchorCache.length > 500) _anchorCache.remove(_anchorCache.keys.first);
  _anchorCache[raw] = parsed;
  return parsed;
}
