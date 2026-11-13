import 'package:flutter/material.dart';

/// Fixed highlight palette shared by the reflow (CSS) and PDF (Flutter)
/// renderers. Keys match the DB `color` column and the JS side uses the
/// same hex strings; Overlayer paints them at .3 opacity so they stay
/// legible across white/sepia/dark color modes.
const annotationHex = {
  'yellow': '#F7D154',
  'green': '#8FD694',
  'blue': '#7EB6F6',
  'red': '#F49A9A',
  'magenta': '#D9A0E8',
};

Color annotationColorOf(String key) {
  final hex = annotationHex[key] ?? annotationHex['yellow']!;
  final raw = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | raw);
}
