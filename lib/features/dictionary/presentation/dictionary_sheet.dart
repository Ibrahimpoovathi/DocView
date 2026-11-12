import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/dv.dart';
import '../data/dictionary_service.dart';
import '../data/dict_registry.dart';
import 'dict_engine.dart';
import 'providers.dart';

/// Opens the dictionary bottom sheet for the tapped/selected [rawWord].
///
/// Safe to call with any selection text: surrounding punctuation is
/// stripped and overlong selections are cut to a single word.
Future<void> showDictionarySheet(
  BuildContext context,
  WidgetRef ref,
  String rawWord,
) async {
  final word = sanitizeLookupWord(rawWord);
  if (word == null || word.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Dv.rXl)),
    ),
    builder: (_) => _DictionarySheet(word: word),
  );
}

/// Keeps a single clean lookup token from free-form selection text.
String? sanitizeLookupWord(String raw) {
  var word = raw.trim();
  // First word only for multi-word selections (v1 looks up single words).
  final space = word.indexOf(RegExp(r'\s'));
  if (space > 0) word = word.substring(0, space);
  word = word
      .replaceAll(
          RegExp(r'^[^\w\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]+'), '')
      .replaceAll(
          RegExp(r'[^\w\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]+$'), '');
  if (word.length > 40) word = word.substring(0, 40);
  return word;
}

class _LookupOutcome {
  const _LookupOutcome({
    this.offlineText,
    this.offlineSource,
    this.onlineEntry,
  });

  final String? offlineText;
  final String? offlineSource;
  final DictionaryEntry? onlineEntry;

  bool get found => (offlineText?.trim().isNotEmpty ?? false) ||
      (onlineEntry?.isEmpty == false);
}

class _DictionarySheet extends ConsumerStatefulWidget {
  const _DictionarySheet({required this.word});

  final String word;

  @override
  ConsumerState<_DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends ConsumerState<_DictionarySheet> {
  final _engine = DictEngineController();
  late Future<_LookupOutcome> _future;

  @override
  void initState() {
    super.initState();
    _future = _lookup();
  }

  Future<_LookupOutcome> _lookup() async {
    // Offline first (user-imported StarDict), then online fallback.
    final prefs = await SharedPreferences.getInstance();
    final dicts = DictRegistry(prefs).list();
    String? offlineText;
    String? offlineSource;
    if (dicts.isNotEmpty) {
      _engine.setImported(dicts.first);
      try {
        offlineText = await _engine.lookup(widget.word);
        offlineSource = dicts.first.bookName;
      } catch (e) {
        debugPrint('[dict] offline lookup failed: $e');
        offlineText = null;
      }
    } else {
      _engine.setImported(null);
    }
    DictionaryEntry? onlineEntry;
    final onlineEnabled =
        prefs.getBool('docview.onlineDictionary') ?? true;
    if (onlineEnabled) {
      onlineEntry =
          await ref.read(onlineDictionaryProvider).lookup(widget.word);
    }
    if (onlineEntry != null && onlineEntry.meanings.isNotEmpty) {
      // Record even "not found" attempts? No — only real hits make history.
      final history = await ref.read(lookupHistoryProvider.future);
      await history.record(widget.word);
    }
    return _LookupOutcome(
      offlineText: offlineText,
      offlineSource: offlineSource,
      onlineEntry: onlineEntry,
    );
  }

  void _retry() {
    setState(() => _future = _lookup());
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        // Hidden 1×1 engine hosting the StarDict WebView (must stay mounted).
        Positioned.fill(
          child: Align(
            alignment: Alignment.topLeft,
            child: DictEngine(controller: _engine),
          ),
        ),
        DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.92,
          minChildSize: 0.3,
          builder: (_, scrollCtrl) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp12, Dv.sp20, Dv.sp8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.word,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<_LookupOutcome>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final outcome = snap.data ?? const _LookupOutcome();
                    if (!outcome.found) {
                      return _EmptyState(
                          word: widget.word, onRetryOnline: _retry);
                    }
                    final offlineHit =
                        outcome.offlineText?.trim().isNotEmpty ?? false;
                    if (offlineHit) {
                      return _OfflineArticle(
                        text: outcome.offlineText!,
                        source: outcome.offlineSource ?? 'Offline dictionary',
                      );
                    }
                    return _OnlineArticle(
                      entry: outcome.onlineEntry!,
                      scrollCtrl: scrollCtrl,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OfflineArticle extends StatelessWidget {
  const _OfflineArticle({required this.text, required this.source});

  final String text;
  final String source;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text_ = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp12, Dv.sp20, Dv.sp24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(text, style: text_.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: Dv.sp12),
          Text(
            'Source · Offline ($source)',
            style: text_.labelSmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

class _OnlineArticle extends StatelessWidget {
  const _OnlineArticle({required this.entry, required this.scrollCtrl});

  final DictionaryEntry entry;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp12, Dv.sp20, Dv.sp24),
      children: [
        if (entry.phonetic != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Dv.sp8),
            child: Text(
              entry.phonetic!,
              style: text.bodyMedium?.copyWith(color: cs.primary),
            ),
          ),
        for (final meaning in entry.meanings) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: Dv.sp8),
              padding: const EdgeInsets.symmetric(
                  horizontal: Dv.sp12, vertical: Dv.sp4),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(Dv.rSm),
              ),
              child: Text(
                meaning.partOfSpeech,
                style: text.labelMedium
                    ?.copyWith(color: cs.onSecondaryContainer),
              ),
            ),
          ),
          for (final def in meaning.definitions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Dv.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.definition, style: text.bodyLarge),
                  if (def.example != null && def.example!.isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.only(top: Dv.sp4, left: Dv.sp12),
                      child: Text(
                        def.example!,
                        style: text.bodyMedium
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: Dv.sp12),
        Text(
          'Source · Online (dictionaryapi.dev)',
          style: text.labelSmall?.copyWith(color: cs.outline),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.word, required this.onRetryOnline});

  final String word;
  final VoidCallback onRetryOnline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dv.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 40, color: cs.outline),
            const SizedBox(height: Dv.sp12),
            Text('No definition found for "$word"', style: text.bodyLarge),
            const SizedBox(height: Dv.sp4),
            Text(
              'Offline dictionaries can be added in Settings.',
              style: text.bodySmall?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: Dv.sp12),
            OutlinedButton.icon(
              onPressed: onRetryOnline,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
