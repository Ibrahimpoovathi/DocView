// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Encrypted on-device storage for the WebDAV account.

@ProviderFor(webdavCredentialStore)
final webdavCredentialStoreProvider = WebdavCredentialStoreProvider._();

/// Encrypted on-device storage for the WebDAV account.

final class WebdavCredentialStoreProvider
    extends
        $FunctionalProvider<
          WebdavCredentialStore,
          WebdavCredentialStore,
          WebdavCredentialStore
        >
    with $Provider<WebdavCredentialStore> {
  /// Encrypted on-device storage for the WebDAV account.
  WebdavCredentialStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'webdavCredentialStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$webdavCredentialStoreHash();

  @$internal
  @override
  $ProviderElement<WebdavCredentialStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WebdavCredentialStore create(Ref ref) {
    return webdavCredentialStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WebdavCredentialStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WebdavCredentialStore>(value),
    );
  }
}

String _$webdavCredentialStoreHash() =>
    r'bffce627334da6abb2aea4f5294258905c5d7441';

/// The configured WebDAV account (null = sync disabled). Loaded from secure
/// storage once at boot; [WebdavAccountStore.save]/[WebdavAccountStore.remove]
/// keep state and storage in step.

@ProviderFor(WebdavAccountStore)
final webdavAccountStoreProvider = WebdavAccountStoreProvider._();

/// The configured WebDAV account (null = sync disabled). Loaded from secure
/// storage once at boot; [WebdavAccountStore.save]/[WebdavAccountStore.remove]
/// keep state and storage in step.
final class WebdavAccountStoreProvider
    extends $AsyncNotifierProvider<WebdavAccountStore, WebdavAccount?> {
  /// The configured WebDAV account (null = sync disabled). Loaded from secure
  /// storage once at boot; [WebdavAccountStore.save]/[WebdavAccountStore.remove]
  /// keep state and storage in step.
  WebdavAccountStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'webdavAccountStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$webdavAccountStoreHash();

  @$internal
  @override
  WebdavAccountStore create() => WebdavAccountStore();
}

String _$webdavAccountStoreHash() =>
    r'4e5967948b49feb0703b16e16d617dd9922a1264';

/// The configured WebDAV account (null = sync disabled). Loaded from secure
/// storage once at boot; [WebdavAccountStore.save]/[WebdavAccountStore.remove]
/// keep state and storage in step.

abstract class _$WebdavAccountStore extends $AsyncNotifier<WebdavAccount?> {
  FutureOr<WebdavAccount?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<WebdavAccount?>, WebdavAccount?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<WebdavAccount?>, WebdavAccount?>,
              AsyncValue<WebdavAccount?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Sync engine bound to the current account; null when sync is disabled.

@ProviderFor(syncEngine)
final syncEngineProvider = SyncEngineProvider._();

/// Sync engine bound to the current account; null when sync is disabled.

final class SyncEngineProvider
    extends $FunctionalProvider<SyncEngine?, SyncEngine?, SyncEngine?>
    with $Provider<SyncEngine?> {
  /// Sync engine bound to the current account; null when sync is disabled.
  SyncEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncEngineHash();

  @$internal
  @override
  $ProviderElement<SyncEngine?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncEngine? create(Ref ref) {
    return syncEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncEngine? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncEngine?>(value),
    );
  }
}

String _$syncEngineHash() => r'c27138c066b6d02ae792e2ee25383beadb686691';

/// Runs a sync cycle; state holds the last result/feedback line ('' while
/// idle). Library screen surfaces it as a snackbar via ref.listen.

@ProviderFor(SyncRunner)
final syncRunnerProvider = SyncRunnerProvider._();

/// Runs a sync cycle; state holds the last result/feedback line ('' while
/// idle). Library screen surfaces it as a snackbar via ref.listen.
final class SyncRunnerProvider extends $NotifierProvider<SyncRunner, String> {
  /// Runs a sync cycle; state holds the last result/feedback line ('' while
  /// idle). Library screen surfaces it as a snackbar via ref.listen.
  SyncRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncRunnerHash();

  @$internal
  @override
  SyncRunner create() => SyncRunner();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$syncRunnerHash() => r'c1625002570d91d1596a4fac7f4587389699ee81';

/// Runs a sync cycle; state holds the last result/feedback line ('' while
/// idle). Library screen surfaces it as a snackbar via ref.listen.

abstract class _$SyncRunner extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
