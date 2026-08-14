import 'rust/api.dart' as frb;

/// The provider lifecycle state, read synchronously via CoproductClient.state
enum ProviderState { notReady, ready, retrying, stale, fatal }

/// Translates the generated provider state into the public enum
ProviderState providerStateFromFrb(frb.ProviderState state) => switch (state) {
      frb.ProviderState.notReady => ProviderState.notReady,
      frb.ProviderState.ready => ProviderState.ready,
      frb.ProviderState.retrying => ProviderState.retrying,
      frb.ProviderState.stale => ProviderState.stale,
      frb.ProviderState.fatal => ProviderState.fatal,
    };
