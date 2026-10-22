// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-wide database (single instance for the process lifetime).

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

/// App-wide database (single instance for the process lifetime).

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// App-wide database (single instance for the process lifetime).
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'6bed5b2a1daeb24872037fdda9cbdcc0f4b4d86f';

@ProviderFor(libraryRepository)
final libraryRepositoryProvider = LibraryRepositoryProvider._();

final class LibraryRepositoryProvider
    extends
        $FunctionalProvider<
          LibraryRepository,
          LibraryRepository,
          LibraryRepository
        >
    with $Provider<LibraryRepository> {
  LibraryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryRepositoryHash();

  @$internal
  @override
  $ProviderElement<LibraryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LibraryRepository create(Ref ref) {
    return libraryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryRepository>(value),
    );
  }
}

String _$libraryRepositoryHash() => r'9b3a64c1b0cbc1531afa8d5ea19186bd2c9b2cac';

@ProviderFor(metadataService)
final metadataServiceProvider = MetadataServiceProvider._();

final class MetadataServiceProvider
    extends
        $FunctionalProvider<MetadataService, MetadataService, MetadataService>
    with $Provider<MetadataService> {
  MetadataServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'metadataServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$metadataServiceHash();

  @$internal
  @override
  $ProviderElement<MetadataService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MetadataService create(Ref ref) {
    return metadataService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetadataService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetadataService>(value),
    );
  }
}

String _$metadataServiceHash() => r'35ab18b11024734186a9c6b286a0223bad29c0bc';

@ProviderFor(importService)
final importServiceProvider = ImportServiceProvider._();

final class ImportServiceProvider
    extends $FunctionalProvider<ImportService, ImportService, ImportService>
    with $Provider<ImportService> {
  ImportServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importServiceHash();

  @$internal
  @override
  $ProviderElement<ImportService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ImportService create(Ref ref) {
    return importService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportService>(value),
    );
  }
}

String _$importServiceHash() => r'e02201570906f635b2aa3f75d5b24b0759405778';

/// Library view state (sort/chip/search) + grid-vs-list presentation mode.

@ProviderFor(LibraryPrefs)
final libraryPrefsProvider = LibraryPrefsProvider._();

/// Library view state (sort/chip/search) + grid-vs-list presentation mode.
final class LibraryPrefsProvider
    extends $NotifierProvider<LibraryPrefs, LibraryPrefsState> {
  /// Library view state (sort/chip/search) + grid-vs-list presentation mode.
  LibraryPrefsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryPrefsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryPrefsHash();

  @$internal
  @override
  LibraryPrefs create() => LibraryPrefs();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryPrefsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryPrefsState>(value),
    );
  }
}

String _$libraryPrefsHash() => r'1c840959ec4bfadb55b905315ba7d1564561657f';

/// Library view state (sort/chip/search) + grid-vs-list presentation mode.

abstract class _$LibraryPrefs extends $Notifier<LibraryPrefsState> {
  LibraryPrefsState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<LibraryPrefsState, LibraryPrefsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LibraryPrefsState, LibraryPrefsState>,
              LibraryPrefsState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Import run state for UI feedback.

@ProviderFor(ImportRunner)
final importRunnerProvider = ImportRunnerProvider._();

/// Import run state for UI feedback.
final class ImportRunnerProvider
    extends $NotifierProvider<ImportRunner, String> {
  /// Import run state for UI feedback.
  ImportRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importRunnerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importRunnerHash();

  @$internal
  @override
  ImportRunner create() => ImportRunner();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$importRunnerHash() => r'431f270317dc5d080b03e13bc4d047e66040e822';

/// Import run state for UI feedback.

abstract class _$ImportRunner extends $Notifier<String> {
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
