/// One text hit: line [index], plus a short surrounding excerpt.
class TextHit {
  const TextHit({
    required this.index,
    required this.pre,
    required this.hit,
    required this.post,
  });

  final int index;
  final String pre;
  final String hit;
  final String post;
}

/// Find [query] in a list of lines, case-insensitive (and accent-sensitive
/// enough for exact substring matching), returning capped excerpts.
List<TextHit> findTextHits(
  List<String> lines,
  String rawQuery, {
  int maxResults = 400,
}) {
  final query = rawQuery.trim();
  if (query.isEmpty) return const [];
  final needle = query.toLowerCase();
  final out = <TextHit>[];

  for (var i = 0; i < lines.length && out.length < maxResults; i++) {
    final line = lines[i];
    final hay = line.toLowerCase();
    var from = 0;
    while (from <= hay.length - needle.length && out.length < maxResults) {
      final at = hay.indexOf(needle, from);
      if (at < 0) break;
      final end = at + needle.length;
      out.add(TextHit(
        index: i,
        pre: line.substring((at - 40).clamp(0, at), at).trimLeft(),
        hit: line.substring(at, end),
        post: line.substring(end, (end + 40).clamp(end, line.length)).trimRight(),
      ));
      from = end;
    }
  }
  return out;
}
