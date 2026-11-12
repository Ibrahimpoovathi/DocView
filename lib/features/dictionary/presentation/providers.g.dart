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

/// Ready-after-first-load history store (shared_preferences caches values
/// once getInstance resolves).

@ProviderFor(lookupHistory)
final lookupHistoryProvider = LookupHistoryProvider._();

/// Ready-after-first-load history store (shared_preferences caches values
/// once getInstance resolves).

final class LookupHistoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<LookupHistory>,
          LookupHistory,
          FutureOr<LookupHistory>
        >
    with $FutureModifier<LookupHistory>, $FutureProvider<LookupHistory> {
  /// Ready-after-first-load history store (shared_preferences caches values
  /// once getInstance resolves).
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
  $FutureProviderElement<LookupHistory> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LookupHistory> create(Ref ref) {
    return lookupHistory(ref);
  }
}

String _$lookupHistoryHash() => r'19dd9368358b9633687640b6309272b859e2f1be';
