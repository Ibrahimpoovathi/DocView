import 'dart:io';

import 'package:flutter/material.dart';

import '../../storage/database.dart';

/// A cover card for a document. Rendering data comes straight from the
/// drift `Document` row to keep this leaf dumb.
class DocCard extends StatelessWidget {
  const DocCard({
    super.key,
    required this.document,
    required this.onOpen,
    required this.onLongPress,
    this.width,
  });

  final Document document;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: document.coverPath != null
          ? Image.file(
              File(document.coverPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => _ph(cs),
            )
          : _ph(cs),
    );

    final card = InkResponse(
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      onTap: onOpen,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.68,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(child: cover),
                    // warm gutter (book spine)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.center,
                            stops: const [0.0, 0.14],
                            colors: [
                              cs.shadow.withValues(alpha: 0.22),
                              cs.shadow.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (document.isFavourite)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(
                          Icons.bookmark_added_rounded,
                          size: 18,
                          color: cs.tertiary,
                          shadows: const [
                            Shadow(blurRadius: 6, color: Colors.black26),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            document.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontSize: 14, height: 1.25),
          ),
          const SizedBox(height: 2),
          Text(
            _subtitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall,
          ),
        ],
      ),
    );

    final w = width;
    return SizedBox(
      width: w,
      child: card,
    );
  }

  String _subtitle() {
    final f = document.format.label;
    final a = document.author;
    return a == null || a.isEmpty ? f : '$f · $a';
  }

  static Widget _ph(ColorScheme cs) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer.withValues(alpha: 0.85),
              cs.secondaryContainer.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.menu_book_rounded,
            color: cs.onPrimaryContainer.withValues(alpha: 0.4),
            size: 34,
          ),
        ),
      );
}
