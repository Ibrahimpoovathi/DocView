import 'package:flutter/material.dart';

import '../design/dv.dart';

/// "Bookish warm" theme — warm paper surfaces, ink text, restrained
/// terracotta accent, serif display type, sans UI type.
abstract final class AppTheme {
  static ThemeData get light => _base(_lightScheme);

  static ThemeData get dark => _base(_darkScheme);

  // --- Color schemes --------------------------------------------------------

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF8C4A32),
    onPrimary: Color(0xFFFFF8F3),
    // ignore: avoid_redundant_argument_values
    primaryContainer: Color(0xFFF6DCC9),
    onPrimaryContainer: Color(0xFF3B2010),
    secondary: Color(0xFF5F6B4F),
    onSecondary: Color(0xFFF8FAF1),
    secondaryContainer: Color(0xFFE2E8D3),
    onSecondaryContainer: Color(0xFF1A2012),
    tertiary: Color(0xFF9A6C22),
    onTertiary: Color(0xFFFFF8EC),
    tertiaryContainer: Color(0xFFF3E3C2),
    onTertiaryContainer: Color(0xFF2E2310),
    error: Color(0xFF8F3A2C),
    onError: Color(0xFFFFF6F1),
    errorContainer: Color(0xFFF8DCD3),
    onErrorContainer: Color(0xFF3B110A),
    surface: Color(0xFFFAF5EC),
    onSurface: Color(0xFF221B12),
    onSurfaceVariant: Color(0xFF55483A),
    outline: Color(0xFF867666),
    outlineVariant: Color(0xFFDACFBE),
    shadow: Color(0xFF221B12),
    inverseSurface: Color(0xFF372E22),
    onInverseSurface: Color(0xFFF9EFE1),
    inversePrimary: Color(0xFFF1BCA2),
    surfaceTint: Color(0xFF8C4A32),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE9B799),
    onPrimary: Color(0xFF46230F),
    primaryContainer: Color(0xFF63331B),
    onPrimaryContainer: Color(0xFFF9DCC8),
    secondary: Color(0xFFC0CCA6),
    onSecondary: Color(0xFF26301A),
    secondaryContainer: Color(0xFF3D4A2E),
    onSecondaryContainer: Color(0xFFDCE8C8),
    tertiary: Color(0xFFDCC386),
    onTertiary: Color(0xFF302509),
    tertiaryContainer: Color(0xFF6D5115),
    onTertiaryContainer: Color(0xFFF6E3B8),
    error: Color(0xFFEFB4A4),
    onError: Color(0xFF4A150B),
    errorContainer: Color(0xFF6E2C1D),
    onErrorContainer: Color(0xFFFBDAD0),
    surface: Color(0xFF191511),
    onSurface: Color(0xFFEEE3D4),
    onSurfaceVariant: Color(0xFFC8B9A9),
    outline: Color(0xFF94846F),
    outlineVariant: Color(0xFF463D32),
    shadow: Color(0xFF000000),
    inverseSurface: Color(0xFFEEE3D4),
    onInverseSurface: Color(0xFF362D22),
    inversePrimary: Color(0xFF9F5C3E),
    surfaceTint: Color(0xFFE9B799),
  );

  // --- Typography -----------------------------------------------------------

  static TextTheme _textTheme(ColorScheme cs) {
    const display = Dv.fontFamilyDisplay;
    const ui = Dv.fontFamilyUi;
    return TextTheme(
      displaySmall: TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: 34,
        height: 1.15,
        letterSpacing: -0.5,
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: 26,
        height: 1.2,
        letterSpacing: -0.3,
        color: cs.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: 21,
        height: 1.2,
        letterSpacing: -0.2,
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: ui,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        height: 1.3,
        color: cs.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: ui,
        fontWeight: FontWeight.w400,
        fontSize: 15.5,
        height: 1.45,
        color: cs.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: ui,
        fontWeight: FontWeight.w400,
        fontSize: 13.5,
        height: 1.4,
        color: cs.onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: ui,
        fontWeight: FontWeight.w500,
        fontSize: 11.5,
        height: 1.3,
        letterSpacing: 0.2,
        color: cs.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontFamily: ui,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.1,
        color: cs.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: ui,
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: ui,
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 0.4,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  // --- Theme assembly -------------------------------------------------------

  static ThemeData _base(ColorScheme cs) {
    final text = _textTheme(cs);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      textTheme: text,
      visualDensity: VisualDensity.comfortable,
      scaffoldBackgroundColor: cs.surface,
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.55),
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
        actionsIconTheme: IconThemeData(color: cs.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        color: cs.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dv.rLg),
          side: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(
              horizontal: Dv.sp20, vertical: Dv.sp12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dv.rMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dv.rMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        hintStyle: text.bodyMedium
            ?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
        labelStyle: text.labelMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dv.rMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dv.rMd),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dv.rMd),
          borderSide: BorderSide(color: cs.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: Dv.sp16, vertical: Dv.sp12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        selectedColor: cs.primaryContainer,
        checkmarkColor: cs.onPrimaryContainer,
        labelStyle: text.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        secondaryLabelStyle: text.labelMedium
            ?.copyWith(color: cs.onPrimaryContainer),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dv.rMd),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: Dv.sp12, vertical: Dv.sp8),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cs.inverseSurface,
        contentTextStyle: text.bodyMedium
            ?.copyWith(color: cs.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dv.rMd),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cs.surface,
        showDragHandle: true,
        dragHandleColor: cs.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(cs.surface.withValues(alpha: 0.98)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Dv.rMd),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dv.rMd),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dv.rXl),
        ),
      ),
    );
  }
}
