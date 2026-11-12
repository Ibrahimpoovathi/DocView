import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/dv.dart';
import '../../sync/data/webdav_sync.dart';
import '../../sync/presentation/sync_providers.dart';
import '../data/dict_registry.dart';

/// Settings: dictionary management (offline StarDict import, per-dictionary
/// removal, online-fallback toggle) + WebDAV sync account.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<ImportedDict>? _dicts;
  bool _importing = false;
  bool _onlineEnabled = true;

  // WebDAV form state (only used when no account is configured yet).
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

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

  // --- WebDAV sync ----------------------------------------------------------

  Future<void> _saveAccount() async {
    if (_saving) return;
    final account = WebdavAccount(
      url: _urlCtrl.text.trim(),
      user: _userCtrl.text.trim(),
      password: _pwdCtrl.text,
    );
    if (!account.isComplete) {
      _snack('Fill in server URL, username and password.');
      return;
    }
    setState(() => _saving = true);
    try {
      final warning =
          await ref.read(webdavAccountStoreProvider.notifier).save(account);
      if (!mounted) return;
      _snack(warning ?? 'Sync account connected.');
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncNow() async {
    final message = await ref.read(syncRunnerProvider.notifier).run();
    if (!mounted) return;
    _snack(message ?? 'Sync unavailable (no account).');
  }

  Future<void> _downloadAll() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    setState(() => _saving = true);
    try {
      final n = await engine.downloadAll(
          onStep: (s) => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1),
                content: Text(s))));
      if (!mounted) return;
      _snack(n == 0 ? 'Everything is already downloaded.' : 'Downloaded $n document(s).');
    } on Object catch (e) {
      if (mounted) _snack('Download failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeAccount() async {
    await ref.read(webdavAccountStoreProvider.notifier).remove();
    if (!mounted) return;
    _urlCtrl.clear();
    _userCtrl.clear();
    _pwdCtrl.clear();
    _snack('Sync account removed (server data untouched).');
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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
          const Divider(),
          ..._syncSection(cs, text),
        ],
      ),
    );
  }

  List<Widget> _syncSection(ColorScheme cs, TextTheme text) {
    final accountAsync = ref.watch(webdavAccountStoreProvider);
    final account = accountAsync.value;
    final busy = ref.watch(syncRunnerProvider) == SyncRunner.running;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp12, Dv.sp20, Dv.sp4),
        child: Text('WebDAV sync', style: text.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp4, Dv.sp20, Dv.sp12),
        child: Text(
          'Sync your library (books, reading positions, collections) with '
          'any WebDAV server — Nextcloud, Synology, etc.',
          style: text.bodySmall?.copyWith(color: cs.outline),
        ),
      ),
      if (accountAsync.isLoading && account == null)
        const Padding(
          padding: EdgeInsets.all(Dv.sp24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (account == null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(Dv.sp20, 0, Dv.sp20, Dv.sp8),
          child: TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://cloud.example.com/remote.php/dav/files/me',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Dv.sp20, 0, Dv.sp20, Dv.sp8),
          child: TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Dv.sp20, 0, Dv.sp20, Dv.sp12),
          child: TextField(
            controller: _pwdCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Dv.sp20, 0, Dv.sp20, Dv.sp16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveAccount,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_outlined),
            label: const Text('Connect & test'),
          ),
        ),
      ] else ...[
        ListTile(
          leading: const Icon(Icons.cloud_done_outlined),
          title: Text(account.user),
          subtitle: Text(account.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Remove account',
            icon: const Icon(Icons.link_off),
            onPressed: _removeAccount,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Dv.sp20, Dv.sp8, Dv.sp20, 0),
          child: Wrap(
            spacing: Dv.sp8,
            runSpacing: Dv.sp8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : _syncNow,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: Text(busy ? 'Syncing…' : 'Sync now'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _downloadAll,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download all'),
              ),
            ],
          ),
        ),
        const SizedBox(height: Dv.sp16),
      ],
    ];
  }
}
