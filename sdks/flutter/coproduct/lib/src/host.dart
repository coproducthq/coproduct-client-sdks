import 'package:flutter/foundation.dart';

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

/// A non-throwing wrapper so the metadata future is observed from creation. An
/// early-build cancellation therefore never surfaces as an unhandled async error
/// while the collector is not yet awaited.
sealed class _MetadataOutcome {}

class _MetadataSuccess extends _MetadataOutcome {
  _MetadataSuccess(this.attributes);
  final Map<String, frb.FrbContextValue> attributes;
}

class _MetadataFailure extends _MetadataOutcome {
  _MetadataFailure(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}

/// A fresh monotonic clock reading elapsed time from now, one per build.
Duration Function() _stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}

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
    Duration Function()? initClock,
    Duration Function()? schedulerClock,
  })  : _bridge = bridge, // ignore: prefer_initializing_formals
        _userAgent = userAgent, // ignore: prefer_initializing_formals
        _createTransport = createTransport, // ignore: prefer_initializing_formals
        _secureStore = secureStore, // ignore: prefer_initializing_formals
        _metadataProviders = metadataProviders, // ignore: prefer_initializing_formals
        _createClient = createClient, // ignore: prefer_initializing_formals
        _bindForeground = bindForeground, // ignore: prefer_initializing_formals
        _reportError = reportError,
        _initClock = initClock, // ignore: prefer_initializing_formals
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
  final Duration Function()? _initClock;
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
    // One monotonic clock and one absolute deadline for the whole convergence
    // budget, captured before any mandatory setup so native setup elapses
    // against the same budget metadata and readiness share
    final clock = _initClock ?? _stopwatchClock();
    final deadline = clock() + config.startupTimeout;

    await _bridge.ensureInitialized();
    if (!isCurrent()) {
      throw const CoproductInitializationCancelled();
    }
    final transport = _createTransport(config.requestTimeout);
    // Start metadata collection concurrently with the FRB initialize, bounded by
    // the shared deadline and cancellation, and observe it from creation so an
    // early failure never becomes an unhandled async error before publish
    final metadata = collectStaticAttributes(
      _metadataProviders,
      deadline: deadline,
      clock: clock,
      cancel: cancel,
      observe: _observeMetadata,
    ).then<_MetadataOutcome>(
      _MetadataSuccess.new,
      onError: (Object error, StackTrace stack) =>
          _MetadataFailure(error, stack),
    );
    return buildRuntime<H, _ActiveRuntime<C>>(
      initHandle: () async {
        final cacheDir = await _bridge.cacheDirectory();
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
        final outcome = await metadata;
        if (!isCurrent()) {
          throw const CoproductInitializationCancelled();
        }
        if (outcome is _MetadataFailure) {
          Error.throwWithStackTrace(outcome.error, outcome.stack);
        }
        await _bridge.setAutoPopulatedAttributes(
            handle, (outcome as _MetadataSuccess).attributes);
        if (!isCurrent()) {
          throw const CoproductInitializationCancelled();
        }
      },
      createRuntime: (handle) {
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
        deadline: deadline,
        clock: clock,
        cancel: cancel,
      ),
      isCurrent: isCurrent,
      onCleanupError: _reportError,
    );
  }
}

/// Surfaces a dropped automatic attribute so the shared startup budget can be
/// tuned on real device measurements. Confined to debug builds by the assert, so
/// it carries no cost and no log noise in a release build
void _observeMetadata(String field, Duration elapsed, {required bool omitted}) {
  if (!omitted) return;
  assert(() {
    debugPrint('coproduct: automatic attribute "$field" omitted after '
        '${elapsed.inMilliseconds}ms');
    return true;
  }());
}
