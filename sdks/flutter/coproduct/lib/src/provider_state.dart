import 'rust/api.dart' as frb;

/// What the SDK is doing, as reported by `CoproductClient.state`.
///
/// Most apps never need it, because reads serve your default value whenever
/// the SDK cannot resolve a flag. Read it for diagnostics, a debug screen, or
/// logging. On a first launch with no saved flags, [retrying] and [stale] can
/// also mean the SDK has no flags at all
enum ProviderState {
  /// The SDK has no flags yet: nothing is saved from an earlier launch, and no
  /// download has arrived. A failed check moves it to [retrying], but a check
  /// that Coproduct asks to slow down leaves it here
  notReady,

  /// The SDK has flags, either downloaded in this session or loaded from the
  /// copy saved on an earlier launch
  ready,

  /// The last check failed, and the SDK is retrying at the normal interval.
  /// Any flags it already had are still served
  retrying,

  /// Five checks in a row have failed, and the SDK now checks less often. Any
  /// flags it already had are still served
  stale,

  /// Checks have stopped for this session.
  ///
  /// A rejected SDK key also deletes the saved flags, so reads serve your
  /// default values. Any other rejection, such as an endpoint that answers
  /// `404`, keeps the flags the SDK had. An endpoint that cannot be reached
  /// leads to [retrying] and [stale] instead. Checks resume only after the app
  /// restarts, or after `Coproduct.shutdown` and a new `Coproduct.initialize`
  fatal,
}

/// Translates the generated provider state into the public enum
ProviderState providerStateFromFrb(frb.ProviderState state) => switch (state) {
      frb.ProviderState.notReady => ProviderState.notReady,
      frb.ProviderState.ready => ProviderState.ready,
      frb.ProviderState.retrying => ProviderState.retrying,
      frb.ProviderState.stale => ProviderState.stale,
      frb.ProviderState.fatal => ProviderState.fatal,
    };
