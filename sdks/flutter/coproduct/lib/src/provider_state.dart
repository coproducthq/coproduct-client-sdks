import 'rust/api.dart' as frb;

/// The provider lifecycle state, read synchronously via CoproductClient.state.
/// [reconciling] is retained for completeness but state never returns it (it is
/// an event-only value in the core), so an exhaustive switch must still include
/// it even though it is unreachable through state
enum ProviderState { notReady, ready, reconciling, retrying, stale, fatal }

/// Translates the generated provider state into the public enum
ProviderState providerStateFromFrb(frb.ProviderState state) => switch (state) {
      frb.ProviderState.notReady => ProviderState.notReady,
      frb.ProviderState.ready => ProviderState.ready,
      frb.ProviderState.reconciling => ProviderState.reconciling,
      frb.ProviderState.retrying => ProviderState.retrying,
      frb.ProviderState.stale => ProviderState.stale,
      frb.ProviderState.fatal => ProviderState.fatal,
    };
