import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/dv.dart';
import '../data/dict_registry.dart';

/// Settings: currently the dictionary management surface (offline StarDict
/// import, per-dictionary removal, online-fallback toggle).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<ImportedDict>? _dicts;
  bool _importing = false;
  bool _onlineEnabled = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dicts = DictRegistry(prefs).list();
      _onlineEnabled = prefs.getBool('docview.onlineDictionary') ?? true;
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      // Multi-select file paths (same picker the library import uses).
      final paths = await fp.FilePicker.pickFileAndDirectoryPaths(
        type: fp.FileType.any,
      );
      if (paths.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final imported = await DictRegistry(prefs).import(paths: paths);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.inverseSurface,
          content: Text(
            imported == null
                ? 'Could not import — needs a .ifo, .idx and .dict(.dz)'
                : 'Imported "${imported.bookName}"'
                    '${imported.wordCount.isEmpty ? '' : ' · ${imported.wordCount} words'}',
          ),
        ),
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _remove(ImportedDict dict) async {
    final prefs = await SharedPreferences.getInstance();
    await DictRegistry(prefs).remove(dict.id);
    await _refresh();
  }

  Future<void> _toggleOnline(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('docview.onlineDictionary', value);
    if (mounted) setState(() => _onlineEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Dv.sp8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp12, Dv.sp20, Dv.sp4),
            child: Text('Dictionaries', style: text.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp4, Dv.sp20, Dv.sp12),
            child: Text(
              'Offline word lookup. Import a StarDict dictionary '
              '(the .ifo, .idx and .dict.dz files that come with it).',
              style: text.bodySmall?.copyWith(color: cs.outline),
            ),
          ),
          if (_dicts == null)
            const Padding(
              padding: EdgeInsets.all(Dv.sp24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_dicts!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dv.sp20),
              child: Text(
                'No offline dictionaries yet — lookups use the online '
                'dictionary only.',
                style: text.bodyMedium,
              ),
            )
          else
            for (final dict in _dicts!)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(dict.bookName),
                subtitle: Text(dict.wordCount.isEmpty
                    ? dict.typeSequence
                    : '${dict.wordCount} words'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(dict),
                ),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp8, Dv.sp20, Dv.sp16),
            child: OutlinedButton.icon(
              onPressed: _importing ? null : _import,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_upload_outlined),
              label: Text(_importing ? 'Importing…' : 'Import StarDict dictionary'),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Online dictionary fallback'),
            subtitle: const Text(
                'dictionaryapi.dev — used when no offline dictionary has the word'),
            value: _onlineEnabled,
            onChanged: _toggleOnline,
          ),
        ],
      ),
    );
  }
}
