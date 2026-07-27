import 'cancellation.dart';
import 'config.dart';
import 'init_identity.dart';
import 'manager.dart';
import 'metadata_collector.dart';
import 'native_bridge.dart';
import 'provider_state.dart';
import 'readiness.dart';
import 'runtime.dart';
import 'runtime_builder.dart';
import 'scheduler.dart';
import 'secure_identity_store.dart';
import 'errors.dart';
import 'http_transport.dart';
import 'rust/api.dart' as frb;

/// Binds a foreground refresh to platform lifecycle events, returning a disposer
/// or null when there is nothing to dispose. Injected so tests drive foreground
/// events without a widget binding.
typedef ForegroundBinder = void Function()? Function(void Function() onForeground);

/// The retained live runtime: the caller-facing client and the coordinator that
/// tears it down. The manager holds this and returns [client] to the caller.
class _ActiveRuntime<C extends Object> {
  _ActiveRuntime(this.client, this.runtime);
  final C client;
  final CoproductRuntime runtime;
}

/// Orchestrates the process-wide initialize and shutdown, composing the lifecycle
/// core with the default transport, secure store, metadata collector, and
/// scheduler. Generic over the opaque handle [H] and the caller-facing client
/// [C] so the whole flow is unit-tested with fakes. The static Coproduct binds it
/// to the real FRB handle and CoproductClient.
class CoproductHost<H extends Object, C extends Object> {
  CoproductHost({
    required NativeBridge<H> bridge,
    required String userAgent,
    required HttpTransport Function(Duration requestTimeout) createTransport,
    required SecureIdentityStore secureStore,
    required MetadataProviders metadataProviders,
    required C Function(H handle) createClient,
    required ForegroundBinder bindForeground,
    required void Function(Object error, StackTrace stack) reportError,
    Duration perProviderTimeout = const Duration(milliseconds: 500),
    Duration Function()? readinessClock,
    Future<void> Function(Duration)? readinessDelay,
    Duration Function()? schedulerClock,
  })  : _bridge = bridge, // ignore: prefer_initializing_formals
        _userAgent = userAgent, // ignore: prefer_initializing_formals
        _createTransport = createTransport, // ignore: prefer_initializing_formals
        _secureStore = secureStore, // ignore: prefer_initializing_formals
        _metadataProviders = metadataProviders, // ignore: prefer_initializing_formals
        _createClient = createClient, // ignore: prefer_initializing_formals
        _bindForeground = bindForeground, // ignore: prefer_initializing_formals
        _reportError = reportError,
        _perProviderTimeout = perProviderTimeout, // ignore: prefer_initializing_formals
        _readinessClock = readinessClock, // ignore: prefer_initializing_formals
        _readinessDelay = readinessDelay, // ignore: prefer_initializing_formals
        _schedulerClock = schedulerClock, // ignore: prefer_initializing_formals
        _manager = CoproductManager<_ActiveRuntime<C>>(
          shutdownClient: (active) => active.runtime.shutdown(),
          onCleanupError: reportError,
        );

  final NativeBridge<H> _bridge;
  final String _userAgent;
  final HttpTransport Function(Duration) _createTransport;
  final SecureIdentityStore _secureStore;
  final MetadataProviders _metadataProviders;
  final C Function(H) _createClient;
  final ForegroundBinder _bindForeground;
  final void Function(Object, StackTrace) _reportError;
  final Duration _perProviderTimeout;
  final Duration Function()? _readinessClock;
  final Future<void> Function(Duration)? _readinessDelay;
  final Duration Function()? _schedulerClock;
  final CoproductManager<_ActiveRuntime<C>> _manager;

  /// Validates the config, then single-flights the initialize through the manager
  /// keyed on the SDK key and normalized config. A joined caller sees the same
  /// client or the same translated error. Returns the caller-facing client.
  Future<C> initialize({
    required String sdkKey,
    CoproductConfig config = const CoproductConfig(),
  }) async {
    final validated = validateConfig(config);
    final identity = InitIdentity(sdkKey, validated);
    try {
      final active = await _manager.initialize(
        identity,
        (generation, cancel, isCurrent) =>
            _build(sdkKey, validated, generation, cancel, isCurrent),
      );
      return active.client;
    } on frb.InitError catch (error) {
      // Translate the generated init error to its public type for every caller,
      // including a joined one that saw the same raw error. Cancellation and
      // already-initialized are already public and never reach here
      throw translateInitError(error);
    }
  }

  /// Tears the current runtime down and clears it, static across the process.
  Future<void> shutdown() => _manager.shutdown();

  Future<_ActiveRuntime<C>> _build(
    String sdkKey,
    CoproductConfig config,
    int generation,
    CancellationSignal cancel,
    bool Function() isCurrent,
  ) async {
    // Load the native library first, before any host resource is allocated, so a
    // library-load failure never leaves an open HTTP client or in-flight metadata
    // work. Idempotent, so a joined caller does not repeat it, and this still runs
    // inside the single-flight claim, so it happens once per generation
    await _bridge.ensureInitialized();
    if (!isCurrent()) {
      throw const CoproductInitializationCancelled();
    }
    final transport = _createTransport(config.requestTimeout);
    // Start static-attribute collection concurrently with the FRB initialize. It
    // is bounded and fail-closed and is awaited only at the publish stage, so a
    // failure before that stage never waits on it and rollback is not blocked
    final metadata = collectStaticAttributes(_metadataProviders,
        perProviderTimeout: _perProviderTimeout);
    return buildRuntime<H, _ActiveRuntime<C>>(
      initHandle: () async {
        final cacheDir = await _bridge.cacheDirectory();
        // Recheck after the cache lookup so a shutdown that landed during it stops
        // the build before it constructs a native handle
        if (!isCurrent()) {
          throw const CoproductInitializationCancelled();
        }
        return _bridge.initialize(
          sdkKey: sdkKey,
          userAgent: _userAgent,
          config: ffiConfigFor(config),
          cacheDir: cacheDir,
          transportRequest: transport.request,
          secureRead: _secureStore.read,
          secureWrite: _secureStore.write,
        );
      },
      disposeTransport: transport.dispose,
      shutdownHandle: _bridge.shutdown,
      publishAttributes: (handle) async {
        final attributes = await metadata;
        // Recheck after metadata collection so a shutdown that landed during it
        // stops the build before it mutates the core context
        if (!isCurrent()) {
          throw const CoproductInitializationCancelled();
        }
        await _bridge.setAutoPopulatedAttributes(handle, attributes);
      },
      createRuntime: (handle) {
        // Build the caller-facing client first, so if it throws no foreground
        // listener has been installed to leak. Binding the foreground listener is
        // the only acquisition here and is done last, immediately before the
        // infallible runtime that owns disposing it. When foreground polling is
        // off, no listener is registered at all
        final client = _createClient(handle);
        final scheduler = Scheduler(
          poll: () => _bridge.pollNow(handle),
          interval: config.pollInterval,
          pollOnForeground: config.pollOnForeground,
          onError: _reportError,
          clock: _schedulerClock,
        );
        final disposeForeground = config.pollOnForeground
            ? _bindForeground(scheduler.onForeground)
            : null;
        final runtime = CoproductRuntime(
          generation: generation,
          scheduler: scheduler,
          transport: transport,
          coreShutdown: () => _bridge.shutdown(handle),
          disposeForeground: disposeForeground,
        );
        return _ActiveRuntime<C>(client, runtime);
      },
      startRuntime: (active) => active.runtime.start(),
      shutdownRuntime: (active) => active.runtime.shutdown(),
      awaitReady: (handle) => awaitInitialReadiness(
        state: () => providerStateFromFrb(_bridge.state(handle)),
        startupTimeout: config.startupTimeout,
        cancel: cancel,
        clock: _readinessClock,
        delay: _readinessDelay,
      ),
      isCurrent: isCurrent,
      onCleanupError: _reportError,
    );
  }
}
