import 'package:flutter/material.dart';

import '../../../../core/design/dv.dart';
import '../domain/viewer_prefs.dart';

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
