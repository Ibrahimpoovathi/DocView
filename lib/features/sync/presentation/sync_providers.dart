import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../library/presentation/providers.dart';
import '../data/sync_engine.dart';
import '../data/webdav_sync.dart';

part 'sync_providers.g.dart';

/// Encrypted on-device storage for the WebDAV account.
@Riverpod(keepAlive: true)
WebdavCredentialStore webdavCredentialStore(Ref ref) => WebdavCredentialStore();

/// The configured WebDAV account (null = sync disabled). Loaded from secure
/// storage once at boot; [WebdavAccountStore.save]/[WebdavAccountStore.remove]
/// keep state and storage in step.
@Riverpod(keepAlive: true)
class WebdavAccountStore extends _$WebdavAccountStore {
  @override
  Future<WebdavAccount?> build() =>
      ref.watch(webdavCredentialStoreProvider).load();

  /// Saves the account; returns an error message on connection test failure
  /// (still persists — the user may be offline or the server temporarily
  /// unreachable), or null when the connection test passed.
  Future<String?> save(WebdavAccount account) async {
    String? warning;
    try {
      await DocviewWebdav.fromAccount(account).testConnection();
    } on Object catch (e) {
      warning = 'Saved, but connection test failed: $e';
    }
    await ref.watch(webdavCredentialStoreProvider).save(account);
    ref.invalidateSelf();
    return warning;
  }

  Future<void> remove() async {
    await ref.watch(webdavCredentialStoreProvider).clear();
    ref.invalidateSelf();
  }
}

/// Sync engine bound to the current account; null when sync is disabled.
@Riverpod(keepAlive: true)
SyncEngine? syncEngine(Ref ref) {
  final account = ref.watch(webdavAccountStoreProvider).value;
  if (account == null) return null;
  return SyncEngine(ref.watch(appDatabaseProvider),
      DocviewWebdav.fromAccount(account));
}

/// Runs a sync cycle; state holds the last result/feedback line ('' while
/// idle). Library screen surfaces it as a snackbar via ref.listen.
@Riverpod(keepAlive: true)
class SyncRunner extends _$SyncRunner {
  @override
  String build() => '';

  bool get _busy => state == running;

  Future<String?> run() async {
    if (_busy) return null;
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return null;
    state = running;
    try {
      final result = await engine.run();
      if (!ref.mounted) return 'Sync finished (provider disposed).';
      return result.summary;
    } on Object catch (e) {
      if (!ref.mounted) return 'Sync failed (provider disposed): $e';
      return 'Sync failed: $e';
    } finally {
      if (ref.mounted) state = '';
    }
  }

  static const running = 'syncing';
}
