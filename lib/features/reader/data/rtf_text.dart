/// A minimal, testable RTF text extractor.
///
/// RTF is a brace-grouped markup stream. Reading *text out of it* does not
/// need a full renderer — it needs a small state machine:
///
/// - `{ … }` groups: `{\*\field …}`-style destination groups and common
///   metadata groups (font tables, colour tables, stylesheets, headerinfo)
///   carry no reading text — their content is skipped.
/// - `\wordN` control words: most are ignored; a few emit content
///   (`\par`/`\line`/`\sect` → newline, `\tab` → tab).
/// - `\'hh` byte escapes decode as Windows-1252 (RTF's default codepage).
/// - `\uNNNN;` emits one Unicode code point and suppresses the next
///   `\ucN` fallback characters (the group's `\uc` level, default 1).
library;

const Map<int, int> _cp1252High = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
  0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
  0x9E: 0x017E, 0x9F: 0x0178,
};

/// Group kinds whose entire content is skipped.
const Set<String> _skipDestinations = {
  'fonttbl', 'colortbl', 'stylesheet', 'info', 'themedata', 'styleschemedata',
  'listtable', 'listoverridetable', 'latentstyles', 'rsidtbl', 'mmathPr',
  'xmlnstbl', 'pict', 'object', 'template', 'ftnsep', 'ftnsepc', 'aftnsep',
  'aftnsepc', 'footer', 'header', 'bkmkdata', 'datasheet',
};

int _cp1252Byte(int byte) => _cp1252High[byte] ?? byte;

/// Extract readable text from an RTF [source].
String extractRtfText(String source) {
  final out = StringBuffer();
  var i = 0;
  var groupDepth = 0;
  var destinationPending = false;
  int? skipUntilDepth;
  var ucLevel = 1;
  var pendingSkip = 0;

  void append(String s) {
    if (skipUntilDepth != null && groupDepth >= skipUntilDepth) return;
    if (pendingSkip > 0) {
      pendingSkip--;
      return;
    }
    out.write(s);
  }

  bool matchesDestination(String word) =>
      destinationPending || _skipDestinations.contains(word);

  while (i < source.length) {
    final ch = source[i];
    switch (ch) {
      case '{':
        groupDepth++;
        i++;
      case '}':
        groupDepth--;
        if (skipUntilDepth != null && groupDepth < skipUntilDepth) {
          skipUntilDepth = null; // destination group closed
        }
        destinationPending = false;
        i++;
      case '\\':
        i++;
        if (i >= source.length) break;
        final c = source[i];
        if (c.codeUnitAt(0) == 0x27) {
          // \'hh hex byte escape (cp1252)
          if (i + 2 < source.length) {
            final hex = int.tryParse(source.substring(i + 1, i + 3), radix: 16);
            if (hex != null) append(String.fromCharCode(_cp1252Byte(hex)));
            i += 3;
          } else {
            i++;
          }
        } else if (c == '\\') {
          append('\\');
          i++;
        } else if (c == '{' || c == '}') {
          append(c);
          i++;
        } else if (c == '~') {
          append(' ');
          i++;
        } else if (c == '-') {
          append('-');
          i++;
        } else if (c == '_') {
          append('-');
          i++;
        } else if (c == '*' ||
            c == '|' ||
            c == ':' ||
            c == '!') {
          // \* destination marker, \| formula, \: sub/table, \! Math — all skip
          if (c == '*') destinationPending = true;
          i++;
        } else if (_isLetter(c)) {
          // control word with optional numeric parameter
          final start = i;
          // first letter
          i++;
          while (i < source.length && _isLetter(source[i])) {
            i++;
          }
          final word = source.substring(start, i);
          var hasParam = false;
          var param = 0;
          if (i < source.length && source[i] == '-') {
            hasParam = true;
            i++;
            var digits = '';
            while (i < source.length && _isDigit(source[i])) {
              digits += source[i];
              i++;
            }
            param = digits.isEmpty ? 0 : -int.parse(digits);
          } else {
            var digits = '';
            while (i < source.length && _isDigit(source[i])) {
              digits += source[i];
              i++;
            }
            if (digits.isNotEmpty) {
              hasParam = true;
              param = int.parse(digits);
            }
          }
          if (i < source.length && source[i] == ' ') {
            i++; // single space delimiter is consumed, not content
          }

          if (word == 'uc' && hasParam) {
            ucLevel = param;
          } else if (word == 'u' && hasParam) {
            // Unicode code point; param is signed 16-bit
            final cp = param < 0 ? param + 65536 : param;
            if (cp > 0xFFFF) {
              // surrogate pair
              final hi = 0xD800 + ((cp - 0x10000) >> 10);
              final lo = 0xDC00 + ((cp - 0x10000) & 0x3FF);
              append(String.fromCharCodes([hi, lo]));
            } else {
              append(String.fromCharCode(cp));
            }
            // the ; delimiter plus ucLevel fallback chars are suppressed
            // (pendingSkip inside append() consumes them; the ';' is
            // reached on the next loop as a plain char)
            pendingSkip = ucLevel;
          } else if (word == 'bin' && hasParam) {
            // \binN skips N raw bytes (seen as one plain char each)
            pendingSkip += param <= 0 ? 0 : param;
          } else if (matchesDestination(word)) {
            skipUntilDepth = groupDepth;
            destinationPending = false;
          } else if (word == 'par' ||
              word == 'line' ||
              word == 'sect') {
            append('\n');
          } else if (word == 'tab') {
            append('\t');
          }
          // everything else: format-only control word → ignore
        } else {
          // unknown escaped char
          i++;
        }
      default:
        // plain character (content or skipped content or fallback char)
        if (ch == ';' && pendingSkip > 0) {
          pendingSkip--; // \uNNNN; delimiter consumes the semicolon
          i++;
          break;
        }
        append(ch);
        i++;
    }
  }

  return _tidy(out.toString());
}

bool _isLetter(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}

/// Collapse the streams of blank lines the parser leaves behind.
String _tidy(String s) {
  final lines = s
      .split('\n')
      .map((l) => l.replaceAll('\t', '    ').trimRight())
      .toList();
  final out = <String>[];
  var blanks = 0;
  for (final line in lines) {
    if (line.isEmpty) {
      blanks++;
      if (blanks <= 1) out.add(line);
    } else {
      blanks = 0;
      out.add(line);
    }
  }
  return out.join('\n').trim();
}
