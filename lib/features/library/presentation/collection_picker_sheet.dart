import 'package:flutter/material.dart';

import '../../../core/design/dv.dart';
import '../../../core/storage/database.dart';

/// Add-to-collections multi-select sheet; returns chosen Set of
/// collection ids (or null if cancelled).
Future<Set<int>?> showCollectionPickerSheet(
  BuildContext context, {
  required List<Collection> collections,
  required Set<int> initialIds,
  required Future<int> Function(String name) createCollection,
}) async {
  final chosen = {...initialIds};
  final result = await showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => _CollectionPickerSheet(
      collections: collections,
      chosen: chosen,
      createCollection: createCollection,
    ),
  );
  return result;
}

class _CollectionPickerSheet extends StatefulWidget {
  const _CollectionPickerSheet({
    required this.collections,
    required this.chosen,
    required this.createCollection,
  });

  final List<Collection> collections;
  final Set<int> chosen;
  final Future<int> Function(String name) createCollection;

  @override
  State<_CollectionPickerSheet> createState() => _CollectionPickerSheetState();
}

class _CollectionPickerSheetState extends State<_CollectionPickerSheet> {
  late final Set<int> _chosen = {...widget.chosen};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Dv.sp24, 0, Dv.sp24, Dv.sp8),
            child: Text('Collections', style: text.titleLarge),
          ),
          if (widget.collections.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Dv.sp24, Dv.sp8, Dv.sp24, Dv.sp16),
              child: Text(
                'No collections yet — create your first one below.',
                style: text.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ...widget.collections.map((c) => CheckboxListTile(
                value: _chosen.contains(c.id),
                onChanged: (v) => setState(
                  () => v == true ? _chosen.add(c.id) : _chosen.remove(c.id),
                ),
                title: Text(c.name, style: text.bodyLarge),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: Dv.sp16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Dv.rMd),
                ),
              )),
          Padding(
            padding: const EdgeInsets.fromLTRB(Dv.sp24, Dv.sp8, Dv.sp24, 0),
            child: Text('New collection', style: text.labelMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Dv.sp24, Dv.sp8, Dv.sp24, Dv.sp16),
            child: _NewCollectionField(
              onCreate: (name) async {
                final id = await widget.createCollection(name);
                _chosen.add(id);
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Dv.sp24, 0, Dv.sp24, Dv.sp16),
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        Navigator.of(context).pop(_chosen);
                      },
                child: const Text('Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewCollectionField extends StatefulWidget {
  const _NewCollectionField({required this.onCreate});
  final Future<void> Function(String name) onCreate;

  @override
  State<_NewCollectionField> createState() => _NewCollectionFieldState();
}

class _NewCollectionFieldState extends State<_NewCollectionField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        hintText: 'e.g. Work, Novels, Study',
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctrl,
          builder: (context, v, _) => IconButton(
            onPressed: v.text.trim().isEmpty
                ? null
                : () async {
                    await widget.onCreate(v.text.trim());
                    _ctrl.clear();
                    if (context.mounted) FocusScope.of(context).unfocus();
                  },
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create',
          ),
        ),
      ),
      onSubmitted: (v) async {
        if (v.trim().isEmpty) return;
        await widget.onCreate(v.trim());
        _ctrl.clear();
        if (context.mounted) FocusScope.of(context).unfocus();
      },
    );
  }
}
