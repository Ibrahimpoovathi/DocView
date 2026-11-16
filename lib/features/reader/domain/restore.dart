/// Validation for values restored from `reading_positions`.
///
/// A stale page number (book re-imported/shorter), a corrupt progress value or
/// an oversized relocator must never be fed into a viewer: pdfrx renders an
/// empty page and foliate can fail to locate the CFI, both of which look like
/// a "blank document" with no error.
const _maxLocationLength = 4096;

/// Clamps a stored (1-based) page number. [pageCount] may be unknown (0/null).
int clampRestoredPage(int? page, int? pageCount) {
  final candidate = page ?? 1;
  if (candidate < 1) return 1;
  final count = pageCount ?? 0;
  if (count > 0 && candidate > count) return count;
  return candidate;
}

/// Returns a finite fraction in 0..1, or null when the stored value is junk.
double? sanitizeProgress(double? progress) {
  if (progress == null || !progress.isFinite) return null;
  if (progress <= 0) return 0;
  if (progress >= 1) return 1;
  return progress;
}

/// Trims and bounds a relocator (CFI/sheet name). Oversized values are almost
/// always corruption and can make the renderer fail silently.
String? sanitizeLocation(String? location) {
  if (location == null) return null;
  final trimmed = location.trim();
  if (trimmed.isEmpty || trimmed.length > _maxLocationLength) return null;
  return trimmed;
}
