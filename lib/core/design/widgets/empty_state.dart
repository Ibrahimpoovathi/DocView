import 'package:flutter/material.dart';

import '../dv.dart';

/// Warm empty state with serif heading copy.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.heading,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String heading;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dv.sp32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primaryContainer.withValues(alpha: 0.55),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Dv.sp24),
                child: Icon(icon, size: 44, color: cs.primary.withValues(alpha: 0.85)),
              ),
            ),
            const SizedBox(height: Dv.sp24),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: text.headlineMedium,
            ),
            const SizedBox(height: Dv.sp8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Dv.sp24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.file_open_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared menu tile for bottom sheets.
class DvSheetTile extends StatelessWidget {
  const DvSheetTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = destructive ? cs.error : cs.onSurface;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: fg),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
      ),
      trailing: trailing,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dv.rMd),
      ),
    );
  }
}
