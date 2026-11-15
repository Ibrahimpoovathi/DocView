import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dv.dart';
import '../../../core/storage/database.dart';
import '../../library/presentation/providers.dart';
import '../domain/annotations.dart';
import 'annotation_palette.dart';
import 'annotation_sheets.dart';

/// All annotations of one document, grouped by kind, with markdown export.
/// [onJump] navigates the reader (page number for PDF, relocator for reflow);
/// the [onUpdateColor] / [onDelete] hooks let the reader keep its overlay
/// layer (JS annotations) in sync after edits made from this list.
Future<void> showAnnotationsList(
  BuildContext context,
  WidgetRef ref,
  Document doc, {
  required void Function(Annotation ann) onJump,
  void Function(Annotation ann, String? color)? onUpdateColor,
  void Function(Annotation ann)? onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
    ),
    builder: (sheetCtx) => _AnnotationsListSheet(
      doc: doc,
      onJump: onJump,
      onUpdateColor: onUpdateColor,
      onDelete: onDelete,
    ),
  );
}

class _AnnotationsListSheet extends ConsumerWidget {
  const _AnnotationsListSheet({
    required this.doc,
    required this.onJump,
    this.onUpdateColor,
    this.onDelete,
  });

  final Document doc;
  final void Function(Annotation ann) onJump;
  final void Function(Annotation ann, String? color)? onUpdateColor;
  final void Function(Annotation ann)? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<Annotation>>(
      stream: ref.watch(annotationsRepositoryProvider).watchForDoc(doc.id),
      builder: (context, snap) {
        final rows = snap.data ?? const <Annotation>[];
        final groups = <(AnnotationKind, String, IconData)>[
          (AnnotationKind.highlight, 'Highlights', Icons.highlight_rounded),
          (AnnotationKind.note, 'Notes', Icons.sticky_note_2_outlined),
          (AnnotationKind.bookmark, 'Bookmarks', Icons.bookmark_rounded),
        ];
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Dv.sp20, Dv.sp16, Dv.sp12, Dv.sp8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Annotations (${rows.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded),
                      tooltip: 'Export as Markdown',
                      onPressed: rows.isEmpty
                          ? null
                          : () => _exportMarkdown(context, rows),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          'No highlights or notes yet.\nSelect text in the '
                          'document to get started.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final (kind, label, icon) in groups)
                            if (rows.any((a) => a.kind == kind)) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    Dv.sp20, Dv.sp8, Dv.sp20, Dv.sp4),
                                child: Row(
                                  children: [
                                    Icon(icon, size: 16, color: cs.primary),
                                    const SizedBox(width: Dv.sp8),
                                    Text(
                                      label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                  ],
                                ),
                              ),
                              for (final a
                                  in rows.where((a) => a.kind == kind))
                                ListTile(
                                  leading: kind == AnnotationKind.highlight
                                      ? Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: annotationColorOf(
                                                    a.color ?? 'yellow')
                                                .withValues(alpha: 0.85),
                                          ),
                                        )
                                      : Icon(icon,
                                          size: 20, color: cs.primary),
                                  title: Text(
                                    _titleOf(a),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: a.note == null
                                      ? null
                                      : Text(
                                          a.note!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    onJump(a);
                                  },
                                  trailing: IconButton(
                                    icon: const Icon(
                                        Icons.more_vert_rounded,
                                        size: 20),
                                    onPressed: () async {
                                      await showAnnotationEditor(
                                        context,
                                        ref,
                                        a,
                                        onChanged: (color) =>
                                            onUpdateColor?.call(a, color),
                                        onDeleted: () => onDelete?.call(a),
                                      );
                                    },
                                  ),
                                ),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _titleOf(Annotation a) {
    final anchor = tryParseAnchor(a.anchor);
    final where = anchor?.page != null
        ? 'Page ${anchor!.page}'
        : a.kind == AnnotationKind.bookmark
            ? 'Bookmark'
            : 'Highlight';
    if (a.excerpt != null && a.excerpt!.isNotEmpty) {
      return '${a.excerpt!} · $where';
    }
    return where;
  }

  Future<void> _exportMarkdown(
    BuildContext context,
    List<Annotation> rows,
  ) async {
    final buf = StringBuffer('# ${doc.title}\n\n');
    if (doc.author != null && doc.author!.isNotEmpty) {
      buf.writeln('**Author:** ${doc.author}\n');
    }
    buf.writeln('_Exported from DocView, '
        '${DateTime.now().toLocal().toString().substring(0, 16)}_\n');
    for (final (kind, label, _) in <(AnnotationKind, String, IconData)>[
      (AnnotationKind.highlight, 'Highlights', Icons.highlight_rounded),
      (AnnotationKind.note, 'Notes', Icons.sticky_note_2_outlined),
      (AnnotationKind.bookmark, 'Bookmarks', Icons.bookmark_rounded),
    ]) {
      final subset = rows.where((a) => a.kind == kind).toList();
      if (subset.isEmpty) continue;
      buf.writeln('## $label\n');
      for (final a in subset) {
        final anchor = tryParseAnchor(a.anchor);
        final loc =
            anchor?.page != null ? ' (page ${anchor!.page})' : '';
        if (a.excerpt != null && a.excerpt!.trim().isNotEmpty) {
          buf.writeln('- "${a.excerpt!.trim()}"$loc');
        } else {
          buf.writeln('- $loc');
        }
        if (a.note != null && a.note!.trim().isNotEmpty) {
          buf.writeln('  - ${a.note!.trim()}');
        }
      }
      buf.writeln();
    }
    final cs = Theme.of(context).colorScheme;
    final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
    final target = await fp.FilePicker.saveFile(
      fileName:
          '${doc.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}-annotations.md',
      bytes: bytes,
      type: fp.FileType.custom,
      allowedExtensions: const ['md'],
    );
    if (!context.mounted) return;
    if (target != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Annotations exported (Markdown)'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.inverseSurface,
        ),
      );
    }
  }
}
