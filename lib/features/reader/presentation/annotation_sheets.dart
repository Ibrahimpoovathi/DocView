import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dv.dart';
import '../../../core/storage/database.dart';
import '../../library/presentation/providers.dart';
import '../domain/annotations.dart';
import 'annotation_palette.dart';

/// Asks the user for note text (used when creating note annotations).
Future<String?> promptNoteText(BuildContext context, {String? initial}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(initial == null ? 'Add note' : 'Edit note'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Write your note…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogCtx, ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Edit/delete sheet for an existing annotation. Mutations go straight to
/// the repository; the reader screen pushes the matching JS/overlay updates
/// through the [onChanged] / [onDeleted] callbacks.
Future<void> showAnnotationEditor(
  BuildContext context,
  WidgetRef ref,
  Annotation ann, {
  required void Function(String? color) onChanged,
  required void Function() onDeleted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
    ),
    builder: (sheetCtx) => _AnnotationEditorSheet(
      ann: ann,
      onChanged: onChanged,
      onDeleted: onDeleted,
    ),
  );
}

class _AnnotationEditorSheet extends ConsumerStatefulWidget {
  const _AnnotationEditorSheet({
    required this.ann,
    required this.onChanged,
    required this.onDeleted,
  });

  final Annotation ann;
  final void Function(String? color) onChanged;
  final void Function() onDeleted;

  @override
  ConsumerState<_AnnotationEditorSheet> createState() =>
      _AnnotationEditorSheetState();
}

class _AnnotationEditorSheetState
    extends ConsumerState<_AnnotationEditorSheet> {
  late final TextEditingController _noteCtrl =
      TextEditingController(text: widget.ann.note ?? '');
  late String? _color = widget.ann.color;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHighlight = widget.ann.kind == AnnotationKind.highlight;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp16, Dv.sp20, Dv.sp20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_iconFor(widget.ann.kind), size: 20, color: cs.primary),
                const SizedBox(width: Dv.sp8),
                Expanded(
                  child: Text(
                    widget.ann.excerpt ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (isHighlight) ...[
              const SizedBox(height: Dv.sp12),
              Row(
                children: [
                  for (final entry in annotationHex.entries)
                    AnnotationColorDot(
                      hex: entry.value,
                      selected: _color == entry.key,
                      onTap: () async {
                        await ref
                            .read(annotationsRepositoryProvider)
                            .update(widget.ann.id, color: entry.key);
                        if (!mounted) return;
                        setState(() => _color = entry.key);
                        widget.onChanged(entry.key);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: Dv.sp12),
            TextField(
              controller: _noteCtrl,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Write your note…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () async {
                    await ref
                        .read(annotationsRepositoryProvider)
                        .update(widget.ann.id, note: _noteCtrl.text.trim());
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
            const SizedBox(height: Dv.sp12),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
              ),
              onPressed: () async {
                await ref
                    .read(annotationsRepositoryProvider)
                    .softDelete(widget.ann.id);
                if (!context.mounted) return;
                widget.onDeleted();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(AnnotationKind kind) => switch (kind) {
      AnnotationKind.highlight => Icons.highlight_rounded,
      AnnotationKind.note => Icons.sticky_note_2_outlined,
      AnnotationKind.bookmark => Icons.bookmark_border_rounded,
    };

class AnnotationColorDot extends StatelessWidget {
  const AnnotationColorDot({
    super.key,
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final raw = int.parse(hex.substring(1), radix: 16);
    final color = Color(0xFF000000 | raw);
    return Padding(
      padding: const EdgeInsets.only(right: Dv.sp12),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.85),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick 5-color chooser for the PDF context menu ("Highlight…").
Future<String?> showHighlightColorPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Dv.sp20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Highlight color',
                style: Theme.of(sheetCtx).textTheme.titleSmall),
            const SizedBox(height: Dv.sp16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final entry in annotationHex.entries)
                  AnnotationColorDot(
                    hex: entry.value,
                    selected: false,
                    onTap: () => Navigator.pop(sheetCtx, entry.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
