import 'package:flutter/material.dart';

import '../../storage/database.dart';
import 'doc_card.dart';

/// "Continue reading" shelf — horizontal snap-scroll of recently opened docs.
class ShelfBar extends StatelessWidget {
  const ShelfBar({
    super.key,
    required this.documents,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<Document> documents;
  final void Function(Document doc) onOpen;
  final void Function(Document doc) onLongPress;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Text('Continue reading', style: text.titleLarge),
              const Spacer(),
              Icon(
                Icons.auto_stories_rounded,
                size: 20,
                color: cs.primary.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 252,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: documents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final doc = documents[i];
              return DocCard(
                document: doc,
                width: 132,
                onOpen: () => onOpen(doc),
                onLongPress: () => onLongPress(doc),
              );
            },
          ),
        ),
      ],
    );
  }
}
