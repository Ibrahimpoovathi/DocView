import 'package:flutter/material.dart';

import '../../../core/design/dv.dart';
import '../../../core/design/widgets/empty_state.dart';
import '../../../core/storage/database.dart';

/// Edit title/author + manage tags for a document. Returns true when
/// something was saved (caller refreshes).
Future<bool> showEditDocSheet(
  BuildContext context, {
  required Document doc,
  required List<Tag> allTags,
  required Set<int> initialTagIds,
  required Future<void> Function(String title, String? author, Set<int> tagIds) onSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => _EditDocSheet(
      doc: doc,
      allTags: allTags,
      initialTagIds: initialTagIds,
      onSave: onSave,
    ),
  );
  return saved ?? false;
}

class _EditDocSheet extends StatefulWidget {
  const _EditDocSheet({
    required this.doc,
    required this.allTags,
    required this.initialTagIds,
    required this.onSave,
  });

  final Document doc;
  final List<Tag> allTags;
  final Set<int> initialTagIds;
  final Future<void> Function(String, String?, Set<int>) onSave;

  @override
  State<_EditDocSheet> createState() => _EditDocSheetState();
}

class _EditDocSheetState extends State<_EditDocSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.doc.title);
  late final TextEditingController _author =
      TextEditingController(text: widget.doc.author ?? '');
  late final Set<int> _tags = {...widget.initialTagIds};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: Dv.sp24,
        right: Dv.sp24,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + Dv.sp16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit details', style: text.titleLarge),
          const SizedBox(height: Dv.sp16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: Dv.sp12),
          TextField(
            controller: _author,
            decoration: const InputDecoration(
              labelText: 'Author (optional)',
            ),
            textInputAction: TextInputAction.done,
          ),
          if (widget.allTags.isNotEmpty) ...[
            const SizedBox(height: Dv.sp16),
            Text('Tags', style: text.labelMedium),
            const SizedBox(height: Dv.sp4),
            Wrap(
              spacing: Dv.sp8,
              runSpacing: Dv.sp8,
              children: widget.allTags.map((t) {
                final sel = _tags.contains(t.id);
                return FilterChip(
                  selected: sel,
                  label: Text(t.name),
                  onSelected: (v) => setState(
                    () => v ? _tags.add(t.id) : _tags.remove(t.id),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            const SizedBox(height: Dv.sp16),
            const DvSheetTile(
              icon: Icons.label_outline_rounded,
              label: 'No tags yet',
            ),
          ],
          const SizedBox(height: Dv.sp20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: Dv.sp8),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        final title =
                            _title.text.trim().isNotEmpty
                                ? _title.text.trim()
                                : widget.doc.title;
                        final author = _author.text.trim().isEmpty
                            ? null
                            : _author.text.trim();
                        await widget.onSave(title, author, _tags);
                        if (context.mounted) Navigator.of(context).pop(true);
                      },
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: Dv.sp8),
        ],
      ),
    );
  }
}
