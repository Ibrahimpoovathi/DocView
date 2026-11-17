import 'package:flutter/material.dart';

import '../../../../core/design/dv.dart';
import '../domain/viewer_prefs.dart';

/// Search bar shared by PDF / reflow / office readers: field, live match
/// count, prev/next, close.
class ReaderSearchBar extends StatelessWidget {
  const ReaderSearchBar({
    super.key,
    required this.controller,
    required this.countText,
    required this.onQuery,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
    this.busy = false,
    this.onCountTap,
  });

  final TextEditingController controller;

  /// '', 'n' while counting, or 'i/n' when navigating matches.
  final String countText;
  final bool busy;
  final ValueChanged<String> onQuery;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onClose;

  /// Optional: tapping the count opens the results overview.
  final VoidCallback? onCountTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(Dv.sp12, Dv.sp8, Dv.sp12, Dv.sp8),
        padding: const EdgeInsets.symmetric(horizontal: Dv.sp12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Dv.rLg),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded),
            const SizedBox(width: Dv.sp8),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search in document',
                  border: InputBorder.none,
                ),
                onChanged: onQuery,
              ),
            ),
            if (busy || countText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Dv.sp8),
                child: GestureDetector(
                  onTap: onCountTap,
                  behavior: HitTestBehavior.opaque,
                  child: Text(countText),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onPrev,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onNext,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar shared by the PDF and reflow readers: outline, search, color
/// mode cycle, page/progress slider.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.current,
    required this.total,
    required this.cs,
    required this.onPage,
    required this.colorMode,
    required this.onColorCycle,
    required this.onSearchOpen,
    required this.onOutline,
    this.fractionMode = false,
    this.searchEnabled = true,
    this.onTypography,
  });

  final int current;
  final int total;
  final ColorScheme cs;
  final ValueChanged<int> onPage;
  final ViewerColorMode colorMode;
  final VoidCallback onColorCycle;
  final VoidCallback onSearchOpen;
  final VoidCallback onOutline;

  /// Reflow readers: current is a 0..1 permille-ish int used on a fraction
  /// slider; onPage still receives 0..1000.
  final bool fractionMode;
  final bool searchEnabled;

  /// Reflow readers only: opens the font-size / line-spacing sheet. Null hides
  /// the button (the PDF reader has no reflowable typography).
  final VoidCallback? onTypography;

  static const _icons = {
    ViewerColorMode.normal: Icons.contrast_rounded,
    ViewerColorMode.sepia: Icons.circle,
    ViewerColorMode.dark: Icons.nights_stay_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final value = fractionMode
        ? current.clamp(0, 1000).toDouble() / 1000
        : current.clamp(1, total < 1 ? 1 : total).toDouble();
    final max = fractionMode ? 1.0 : (total < 1 ? 1 : total).toDouble();
    final divisions = fractionMode ? 1000 : (total < 2 ? null : total - 1);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Outline',
              onPressed: onOutline,
              icon: const Icon(Icons.format_list_bulleted_rounded),
            ),
            if (searchEnabled)
              IconButton(
                tooltip: 'Search',
                onPressed: onSearchOpen,
                icon: const Icon(Icons.search_rounded),
              )
            else
              const SizedBox(width: 48),
            IconButton(
              tooltip: 'Color: $colorMode',
              onPressed: onColorCycle,
              icon: Icon(_icons[colorMode] ?? Icons.contrast_rounded),
            ),
            if (onTypography != null)
              IconButton(
                tooltip: 'Text size and spacing',
                onPressed: onTypography,
                icon: const Icon(Icons.text_fields_rounded),
              ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: value,
                  max: max,
                  divisions: divisions,
                  onChanged: fractionMode
                      ? (v) => onPage((v * 1000).round())
                      : (v) => onPage(v.round().clamp(1, total)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: Dv.sp12),
              child: Text(
                fractionMode
                    ? '${(value * 100).toStringAsFixed(0)}%'
                    : '$current / $total',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
