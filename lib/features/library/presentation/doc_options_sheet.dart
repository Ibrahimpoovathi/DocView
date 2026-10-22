import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dv.dart';
import '../../../core/design/widgets/empty_state.dart';
import '../../../core/storage/database.dart';
import 'collection_picker_sheet.dart';
import 'edit_doc_sheet.dart';
import 'providers.dart';

/// Per-document action sheet (favourite, edit details, collections, tags,
/// export, delete).
Future<void> showDocOptionsSheet(
  BuildContext context,
  WidgetRef ref,
  Document doc,
) async {
  final repo = ref.read(libraryRepositoryProvider);

  final allTags = await repo.watchTags().first;
  final tagIds = await repo.tagIdsFor(doc.id);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) {
      final cs = Theme.of(sheetCtx).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Dv.sp24, 0, Dv.sp24, Dv.sp4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(sheetCtx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${doc.format.label}${doc.author == null ? '' : ' · ${doc.author}'}',
                      style: Theme.of(sheetCtx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Divider(),
              DvSheetTile(
                icon: doc.isFavourite
                    ? Icons.bookmark_added_rounded
                    : Icons.bookmark_add_outlined,
                label: doc.isFavourite
                    ? 'Remove bookmark'
                    : 'Add to bookmarks',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  repo.toggleFavourite(doc.id, !doc.isFavourite);
                },
              ),
              DvSheetTile(
                icon: Icons.edit_note_rounded,
                label: 'Edit details',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _editDetails(context, ref, doc, allTags, tagIds);
                },
              ),
              DvSheetTile(
                icon: Icons.collections_bookmark_outlined,
                label: 'Add to collection',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _pickCollections(context, ref, doc);
                },
              ),
              DvSheetTile(
                icon: Icons.ios_share_rounded,
                label: 'Export a copy',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _exportCopy(context, ref, doc);
                },
              ),
              DvSheetTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                destructive: true,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmDelete(sheetCtx, ref, doc, cs);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _editDetails(
  BuildContext context,
  WidgetRef ref,
  Document doc,
  List<Tag> allTags,
  Set<int> tagIds,
) async {
  final repo = ref.read(libraryRepositoryProvider);
  await showEditDocSheet(
    context,
    doc: doc,
    allTags: allTags,
    initialTagIds: tagIds,
    onSave: (title, author, tags) async {
      await repo.updateFields(doc.id, title: title, author: author);
      await repo.setDocumentTags(doc.id, tags);
    },
  );
}

Future<void> _pickCollections(
  BuildContext context,
  WidgetRef ref,
  Document doc,
) async {
  final repo = ref.read(libraryRepositoryProvider);
  final collections = await repo.watchCollections().first;
  final currentIds = await repo.collectionIdsFor(doc.id);
  if (!context.mounted) return;
  final picked = await showCollectionPickerSheet(
    context,
    collections: collections,
    initialIds: currentIds,
    createCollection: repo.createCollection,
  );
  if (picked != null) await repo.setDocumentCollections(doc.id, picked);
}

Future<void> _exportCopy(
  BuildContext context,
  WidgetRef ref,
  Document doc,
) async {
  final cs = Theme.of(context).colorScheme;
  final ext = doc.originalName.split('.').last.toLowerCase();
  final fileName = '${doc.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.$ext';
  final bytes = await File(doc.storedPath).readAsBytes();
  final target = await fp.FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    type: fp.FileType.custom,
    allowedExtensions: [ext],
  );
  if (target == null) return;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copy saved ($fileName)'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
      ),
    );
  }
}

void _confirmDelete(
  BuildContext sheetCtx,
  WidgetRef ref,
  Document doc,
  ColorScheme cs,
) {
  showDialog<void>(
    context: sheetCtx,
    builder: (dlgCtx) => AlertDialog(
      title: const Text('Delete this document?'),
      content: Text(
        '"${doc.title}" will be removed from your library and its stored copy deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dlgCtx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error),
          onPressed: () {
            Navigator.of(dlgCtx).pop();
            ref
                .read(libraryRepositoryProvider)
                .deleteDocument(doc.id);
          },
          child: Text('Delete', style: TextStyle(color: cs.onError)),
        ),
      ],
    ),
  );
}
