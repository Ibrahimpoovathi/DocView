import 'package:flutter/material.dart';


/// Paper-toned cover placeholder with a soft sweep, used while metadata or
/// covers resolve.
class SkeletonDocCard extends StatefulWidget {
  const SkeletonDocCard({super.key, this.width});
  final double? width;

  @override
  State<SkeletonDocCard> createState() => _SkeletonDocCardState();
}

class _SkeletonDocCardState extends State<SkeletonDocCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.68,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => _Sweep(t: _c.value),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _Bar(cs: cs, w: 90),
          const SizedBox(height: 6),
          _Bar(cs: cs, w: 56),
        ],
      ),
    );
  }
}

class _Sweep extends StatelessWidget {
  const _Sweep({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: 0.6,
      child: Transform.translate(
        offset: Offset((t * 2 - 0.5) * 200, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                cs.surface.withValues(alpha: 0),
                cs.surface.withValues(alpha: 0.7),
                cs.surface.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.cs, required this.w});
  final ColorScheme cs;
  final double w;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SizedBox(width: w, height: 10),
      );
}
