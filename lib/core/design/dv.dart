import 'package:flutter/material.dart';

/// DocView design tokens — "bookish warm" design language.
///
/// TF = typography family name; every spacing/radius/shadow/motion value
/// comes from here, never inline magic numbers.
abstract final class Dv {
  // Fonts -------------------------------------------------------------------- 
  /// Display serif for titles, headings, empty-state copy.
  static const fontFamilyDisplay = 'Fraunces';

  /// UI sans for body, labels, buttons.
  static const fontFamilyUi = 'Inter';

  // Spacing ------------------------------------------------------------------
  static const double sp4 = 4;
  static const double sp8 = 8;
  static const double sp12 = 12;
  static const double sp16 = 16;
  static const double sp20 = 20;
  static const double sp24 = 24;
  static const double sp32 = 32;

  // Radii --------------------------------------------------------------------
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 20;

  // Card geometry ------------------------------------------------------------
  /// Width-to-height ratio of a book cover card (≈ 2:3).
  static const double coverAspectRatio = 0.68;
  static const double shelfCardWidth = 132;

  // Motion -------------------------------------------------------------------
  static const Duration pressIn = Duration(milliseconds: 120);
  static const Duration settle = Duration(milliseconds: 260);
  static const Duration stagger = Duration(milliseconds: 32);
  static const Duration entrance = Duration(milliseconds: 420);
  static const Curve settleCurve = Curves.easeOutCubic;
  static const Curve entranceCurve = Curves.easeOutCubic;

  // Shadows (paper depth) ----------------------------------------------------
  static List<BoxShadow> paperShadow(BuildContext context) => [
        BoxShadow(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
          spreadRadius: -2,
        ),
        BoxShadow(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.06),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// The warm gradient wash behind cover spines (left edge).
  static LinearGradient spineWash(Color base) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.center,
        stops: const [0.0, 0.12],
        colors: [base.withValues(alpha: 0.30), base.withValues(alpha: 0.0)],
      );
}
