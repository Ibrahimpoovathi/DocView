// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(onlineDictionary)
final onlineDictionaryProvider = OnlineDictionaryProvider._();

final class OnlineDictionaryProvider
    extends
        $FunctionalProvider<
          OnlineDictionary,
          OnlineDictionary,
          OnlineDictionary
        >
    with $Provider<OnlineDictionary> {
  OnlineDictionaryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onlineDictionaryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onlineDictionaryHash();

  @$internal
  @override
  $ProviderElement<OnlineDictionary> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OnlineDictionary create(Ref ref) {
    return onlineDictionary(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnlineDictionary value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnlineDictionary>(value),
    );
  }
}

String _$onlineDictionaryHash() => r'674f7ad99614bb34fc15ba2cac1dd49e7b131ca3';

/// History store backed by the single shared_preferences instance.

@ProviderFor(lookupHistory)
final lookupHistoryProvider = LookupHistoryProvider._();

/// History store backed by the single shared_preferences instance.

final class LookupHistoryProvider
    extends $FunctionalProvider<LookupHistory, LookupHistory, LookupHistory>
    with $Provider<LookupHistory> {
  /// History store backed by the single shared_preferences instance.
  LookupHistoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lookupHistoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lookupHistoryHash();

  @$internal
  @override
  $ProviderElement<LookupHistory> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LookupHistory create(Ref ref) {
    return lookupHistory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LookupHistory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LookupHistory>(value),
    );
  }
}

String _$lookupHistoryHash() => r'8fd7d56791dac93f35403a3f569345d1afd6e8ff';
