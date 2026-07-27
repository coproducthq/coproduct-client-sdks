import 'dart:async';

import 'package:coproduct/src/config.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/host.dart';
import 'package:coproduct/src/http_transport.dart';
import 'package:coproduct/src/metadata_collector.dart';
import 'package:coproduct/src/native_bridge.dart';
import 'package:coproduct/src/secure_identity_store.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

/// A stand-in for the opaque FRB handle, one per fake initialize.
class _FakeHandle {
  _FakeHandle(this.id);
  final int id;
}

/// The caller-facing client the host returns in tests, carrying its handle so a
/// test can assert which handle was wrapped.
class _FakeClient {
  _FakeClient(this.handle);
  final _FakeHandle handle;
}

/// An in-memory KeyValueStore so the secure store never touches a platform
/// channel in tests.
class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// An http.Client that records close, so a test can assert the transport was
/// disposed. send delegates to a MockClient returning 200.
class _RecordingClient extends http.BaseClient {
  bool closed = false;
  final http.Client _inner = MockClient((_) async => http.Response('{}', 200));
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);
  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

/// A ForegroundBinder that records binds and disposes and captures the callback,
/// so a test can assert the listener was installed, disposed, or never bound.
class _RecordingForeground {
  int binds = 0;
  int disposes = 0;
  void Function()? onForeground;
  ForegroundBinder get binder => (callback) {
        binds++;
        onForeground = callback;
        return () => disposes++;
      };
}

/// A scriptable NativeBridge. Records the initialize arguments and captured host
/// closures, counts the one-time native operations, tracks the order of attribute
/// install versus client creation, and returns a controllable provider state and
/// poll outcome. Can gate or fail the initialize and fail the publish.
class _FakeBridge implements NativeBridge<_FakeHandle> {
  _FakeBridge({this.stateValue = frb.ProviderState.notReady});

  frb.ProviderState stateValue;
  int ensureInitializedCalls = 0;
  int cacheDirectoryCalls = 0;
  int handleCounter = 0;

  // Captured initialize arguments and closures
  String? sdkKey;
  String? userAgent;
  frb.FfiConfig? config;
  String? cacheDir;
  FutureOr<frb.HttpResponse> Function(frb.HttpRequest)? transportRequest;
  FutureOr<String?> Function(String)? secureRead;
  FutureOr<void> Function(String, String)? secureWrite;

  // Ordering probes
  int clientsCreated = 0;
  int? attributesInstalledAtClientCount;
  Map<String, frb.FrbContextValue>? installedAttributes;

  int pollCalls = 0;
  final Completer<void> firstPoll = Completer<void>();
  int shutdownCalls = 0;

  // Optional controls and entry handshakes, so a test can prove a phase has
  // actually been entered rather than merely not-yet-finished
  Completer<void>? ensureInitializedGate; // suspends the library load
  final Completer<void> ensureInitializedEntered = Completer<void>();
  Completer<void>? cacheDirectoryGate; // suspends the cache lookup
  final Completer<void> cacheDirectoryEntered = Completer<void>();
  Completer<void>? initGate; // suspends the FRB initialize so a test can race it
  final Completer<void> initializeEntered = Completer<void>();
  Object? initError; // thrown from the FRB initialize
  bool publishThrows = false; // fails setAutoPopulatedAttributes

  @override
  Future<void> ensureInitialized() async {
    ensureInitializedCalls++;
    if (!ensureInitializedEntered.isCompleted) ensureInitializedEntered.complete();
    if (ensureInitializedGate != null) await ensureInitializedGate!.future;
  }

  @override
  Future<String> cacheDirectory() async {
    cacheDirectoryCalls++;
    if (!cacheDirectoryEntered.isCompleted) cacheDirectoryEntered.complete();
    if (cacheDirectoryGate != null) await cacheDirectoryGate!.future;
    return '/fake/cache';
  }

  @override
  Future<_FakeHandle> initialize({
    required String sdkKey,
    required String userAgent,
    required frb.FfiConfig config,
    required String cacheDir,
    required FutureOr<frb.HttpResponse> Function(frb.HttpRequest) transportRequest,
    required FutureOr<String?> Function(String) secureRead,
    required FutureOr<void> Function(String, String) secureWrite,
  }) async {
    this.sdkKey = sdkKey;
    this.userAgent = userAgent;
    this.config = config;
    this.cacheDir = cacheDir;
    this.transportRequest = transportRequest;
    this.secureRead = secureRead;
    this.secureWrite = secureWrite;
    if (!initializeEntered.isCompleted) initializeEntered.complete();
    if (initGate != null) await initGate!.future;
    if (initError != null) throw initError!;
    return _FakeHandle(++handleCounter);
  }

  @override
  Future<void> setAutoPopulatedAttributes(
      _FakeHandle handle, Map<String, frb.FrbContextValue> attributes) async {
    attributesInstalledAtClientCount = clientsCreated;
    installedAttributes = attributes;
    if (publishThrows) throw StateError('publish failed');
  }

  @override
  frb.ProviderState state(_FakeHandle handle) => stateValue;

  @override
  Future<frb.PollOutcome> pollNow(_FakeHandle handle) async {
    pollCalls++;
    if (!firstPoll.isCompleted) firstPoll.complete();
    return const frb.PollOutcome.updated();
  }

  @override
  Future<void> shutdown(_FakeHandle handle) async => shutdownCalls++;
}

/// Metadata providers returning a fixed value per field.
MetadataProviders _providers() => MetadataProviders(
      platform: () async => 'android',
      osVersion: () async => '14',
      appVersion: () async => '1.2.3',
      appBuild: () async => '42',
      locale: () async => 'en-US',
      timezone: () async => 'America/New_York',
    );

CoproductHost<_FakeHandle, _FakeClient> _host(
  _FakeBridge bridge, {
  _MemoryStore? store,
  MetadataProviders? providers,
  http.Client? transportClient,
  _RecordingForeground? foreground,
  Duration Function()? readinessClock,
  Future<void> Function(Duration)? readinessDelay,
}) {
  return CoproductHost<_FakeHandle, _FakeClient>(
    bridge: bridge,
    userAgent: 'coproduct-flutter/test',
    createTransport: (requestTimeout) => HttpTransport(
        client: transportClient ??
            MockClient((_) async => http.Response('{}', 200)),
        requestTimeout: requestTimeout),
    secureStore: SecureIdentityStore(
        backing: store ?? _MemoryStore(),
        operationTimeout: const Duration(seconds: 1)),
    metadataProviders: providers ?? _providers(),
    createClient: (h) {
      bridge.clientsCreated++;
      return _FakeClient(h);
    },
    bindForeground: foreground?.binder ?? (onForeground) => null,
    reportError: (e, s) {},
    readinessClock: readinessClock,
    readinessDelay: readinessDelay,
  );
}

void main() {
  test('initialize wires the config, User-Agent, cache dir, and host closures',
      () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(bridge);

    final client = await host.initialize(
      sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww',
      config: const CoproductConfig(
        pollInterval: Duration(seconds: 45),
        startupTimeout: Duration(seconds: 2),
      ),
    );

    expect(client.handle.id, 1);
    expect(bridge.ensureInitializedCalls, 1);
    expect(bridge.sdkKey, 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');
    expect(bridge.userAgent, 'coproduct-flutter/test');
    expect(bridge.cacheDir, '/fake/cache');
    expect(bridge.config!.pollIntervalUs, 45 * 1000 * 1000);
    expect(bridge.config!.startupTimeoutUs, 2 * 1000 * 1000);
    expect(bridge.secureRead, isNotNull);
    expect(bridge.secureWrite, isNotNull);
    expect(bridge.transportRequest, isNotNull);

    await host.shutdown();
  });

  test('auto-populated attributes are installed before the client is created',
      () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(bridge);

    await host.initialize(sdkKey: 'cpk_mob_a');

    // The install ran while no client had yet been created
    expect(bridge.attributesInstalledAtClientCount, 0);
    expect(bridge.installedAttributes, isNotNull);
    expect(bridge.installedAttributes!['platform'],
        const frb.FrbContextValue.string('android'));
    expect(bridge.installedAttributes!['timezone'],
        const frb.FrbContextValue.string('America/New_York'));

    await host.shutdown();
  });

  test('metadata collection overlaps the FRB initialize', () async {
    // Park a metadata provider, then prove the FRB initialize enters while it is
    // still in flight. This is bidirectional overlap, not merely metadata running
    // while init is parked, so a regression that collected metadata serially
    // before the handle build would hang here rather than pass
    final metadataGate = Completer<void>();
    final metadataStarted = Completer<void>();
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(
      bridge,
      providers: MetadataProviders(
        platform: () async {
          if (!metadataStarted.isCompleted) metadataStarted.complete();
          await metadataGate.future;
          return 'android';
        },
        osVersion: () async => '14',
        appVersion: () async => '1.2.3',
        appBuild: () async => '42',
        locale: () async => 'en-US',
        timezone: () async => 'America/New_York',
      ),
    );

    final pending = host.initialize(sdkKey: 'cpk_mob_a');
    await metadataStarted.future;
    await bridge.initializeEntered.future;
    expect(metadataGate.isCompleted, isFalse);
    metadataGate.complete();
    await pending;
    await host.shutdown();
  });

  test('the native library loads before any transport or metadata work',
      () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
      ..ensureInitializedGate = Completer<void>();
    var transportsCreated = 0;
    final metadataStarted = Completer<void>();
    final host = CoproductHost<_FakeHandle, _FakeClient>(
      bridge: bridge,
      userAgent: 'coproduct-flutter/test',
      createTransport: (t) {
        transportsCreated++;
        return HttpTransport(
            client: MockClient((_) async => http.Response('{}', 200)),
            requestTimeout: t);
      },
      secureStore: SecureIdentityStore(
          backing: _MemoryStore(), operationTimeout: const Duration(seconds: 1)),
      metadataProviders: MetadataProviders(
        platform: () async {
          if (!metadataStarted.isCompleted) metadataStarted.complete();
          return 'android';
        },
        osVersion: () async => '14',
        appVersion: () async => '1.2.3',
        appBuild: () async => '42',
        locale: () async => 'en-US',
        timezone: () async => 'America/New_York',
      ),
      createClient: (h) => _FakeClient(h),
      bindForeground: (onForeground) => null,
      reportError: (e, s) {},
    );

    final pending = host.initialize(sdkKey: 'cpk_mob_a');
    await bridge.ensureInitializedEntered.future;
    // While the library load is gated, no transport is opened and no metadata
    // provider has run
    expect(transportsCreated, 0);
    expect(metadataStarted.isCompleted, isFalse);
    bridge.ensureInitializedGate!.complete();
    await pending;
    // The later phases ran once the library was ready
    expect(transportsCreated, 1);
    expect(metadataStarted.isCompleted, isTrue);
    await host.shutdown();
  });

  test('the scheduler polls immediately on start', () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(bridge);

    await host.initialize(sdkKey: 'cpk_mob_a');
    expect(bridge.firstPoll.isCompleted, isTrue);
    expect(bridge.pollCalls, greaterThan(0));

    await host.shutdown();
  });

  test('a matching concurrent initialize joins one build and one native init',
      () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(bridge);

    final a = host.initialize(sdkKey: 'cpk_mob_a');
    final b = host.initialize(sdkKey: 'cpk_mob_a');
    final ca = await a;
    final cb = await b;
    expect(identical(ca, cb), isTrue);
    expect(bridge.handleCounter, 1); // one FRB initialize
    expect(bridge.ensureInitializedCalls, 1); // library loaded once
    expect(bridge.cacheDirectoryCalls, 1); // cache dir resolved once

    await host.shutdown();
  });

  test('a mismatching initialize is rejected without leaking the key', () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(bridge);

    await host.initialize(sdkKey: 'cpk_mob_a');
    Object? caught;
    try {
      await host.initialize(sdkKey: 'cpk_mob_b');
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<CoproductAlreadyInitialized>());
    expect(caught.toString().contains('cpk_mob_b'), isFalse);

    await host.shutdown();
  });

  test('shutdown disposes the foreground listener and clears the runtime, so a '
      'fresh initialize builds again', () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final foreground = _RecordingForeground();
    final host = _host(bridge, foreground: foreground);

    await host.initialize(sdkKey: 'cpk_mob_a');
    expect(foreground.binds, 1);
    await host.shutdown();
    expect(bridge.shutdownCalls, greaterThan(0));
    expect(foreground.disposes, 1); // the foreground disposer ran

    final again = await host.initialize(sdkKey: 'cpk_mob_a');
    expect(again.handle.id, 2); // a new FRB initialize ran
    await host.shutdown();
  });

  test('a false pollOnForeground registers no foreground listener', () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final foreground = _RecordingForeground();
    final host = _host(bridge, foreground: foreground);

    await host.initialize(
        sdkKey: 'cpk_mob_a',
        config: const CoproductConfig(pollOnForeground: false));
    expect(foreground.binds, 0);

    await host.shutdown();
  });

  test('an FRB init failure disposes the transport and surfaces the public error',
      () async {
    final transport = _RecordingClient();
    final bridge = _FakeBridge()..initError = const frb.InitError.missingSdkKey();
    final host = _host(bridge, transportClient: transport);

    await expectLater(
        host.initialize(sdkKey: ''), throwsA(isA<MissingSdkKey>()));
    expect(transport.closed, isTrue);
  });

  test('an attribute publish failure shuts down the handle and transport',
      () async {
    final transport = _RecordingClient();
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
      ..publishThrows = true;
    final host = _host(bridge, transportClient: transport);

    // A non-init error propagates unchanged (translation is narrow), and both the
    // handle and the transport are torn down on this pre-runtime failure
    await expectLater(
        host.initialize(sdkKey: 'cpk_mob_a'), throwsA(isA<StateError>()));
    expect(bridge.shutdownCalls, greaterThan(0));
    expect(transport.closed, isTrue);
  });

  test('a client construction failure installs no listener and cleans up',
      () async {
    final transport = _RecordingClient();
    final foreground = _RecordingForeground();
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = CoproductHost<_FakeHandle, _FakeClient>(
      bridge: bridge,
      userAgent: 'coproduct-flutter/test',
      createTransport: (t) => HttpTransport(client: transport, requestTimeout: t),
      secureStore: SecureIdentityStore(
          backing: _MemoryStore(), operationTimeout: const Duration(seconds: 1)),
      metadataProviders: _providers(),
      createClient: (h) => throw StateError('client boom'),
      bindForeground: foreground.binder,
      reportError: (e, s) {},
    );

    await expectLater(
        host.initialize(sdkKey: 'cpk_mob_a'), throwsA(isA<StateError>()));
    expect(foreground.binds, 0); // createClient threw before any bind
    expect(bridge.shutdownCalls, greaterThan(0)); // handle shut down
    expect(transport.closed, isTrue); // transport disposed
  });

  test('a shutdown during the readiness wait cancels through the runtime teardown',
      () async {
    // State never leaves notReady and the readiness delay never completes, so the
    // wait sits until cancellation. Gate on the delay being entered, so the build
    // is proven to be inside the real readiness wait rather than an earlier stage,
    // and a fixed clock keeps the deadline ahead so nothing else ends the wait. A
    // mis-wired CancellationSignal would leave this hanging instead of passing
    final bridge = _FakeBridge(stateValue: frb.ProviderState.notReady);
    final foreground = _RecordingForeground();
    final readinessEntered = Completer<void>();
    final host = _host(
      bridge,
      foreground: foreground,
      readinessClock: () => Duration.zero,
      readinessDelay: (_) {
        if (!readinessEntered.isCompleted) readinessEntered.complete();
        return Completer<void>().future;
      },
    );

    final pending = host.initialize(sdkKey: 'cpk_mob_a');
    final expectation =
        expectLater(pending, throwsA(isA<CoproductInitializationCancelled>()));
    await readinessEntered.future; // the build is now parked in the readiness wait
    await host.shutdown();
    await expectation;
    // The rollback used runtime shutdown, which disposes the foreground listener,
    // proving the post-runtime cancellation path is the runtime teardown, not a
    // separate handle/transport cleanup
    expect(foreground.disposes, greaterThan(0));
  });

  test('a shutdown during the cache lookup cancels before the native initialize',
      () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
      ..cacheDirectoryGate = Completer<void>();
    final host = _host(bridge);

    final pending = host.initialize(sdkKey: 'cpk_mob_a');
    await bridge.cacheDirectoryEntered.future;
    // Supersede while the cache lookup is pending. shutdown bumps the generation
    // and cancels synchronously, so it is captured but not awaited yet
    final shutdown = host.shutdown();
    bridge.cacheDirectoryGate!.complete();
    await expectLater(
        pending, throwsA(isA<CoproductInitializationCancelled>()));
    await shutdown;
    expect(bridge.initializeEntered.isCompleted, isFalse);
  });

  test('a shutdown during metadata collection cancels before attributes install',
      () async {
    final metadataGate = Completer<void>();
    final metadataStarted = Completer<void>();
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(
      bridge,
      providers: MetadataProviders(
        platform: () async {
          if (!metadataStarted.isCompleted) metadataStarted.complete();
          await metadataGate.future;
          return 'android';
        },
        osVersion: () async => '14',
        appVersion: () async => '1.2.3',
        appBuild: () async => '42',
        locale: () async => 'en-US',
        timezone: () async => 'America/New_York',
      ),
    );

    final pending = host.initialize(sdkKey: 'cpk_mob_a');
    await metadataStarted.future;
    await bridge.initializeEntered.future;
    // Drain past the native initialize and the pre-publish generation check, so the
    // build is genuinely parked at the metadata await and only the intra-publish
    // recheck can catch the shutdown. handleCounter confirms the handle was built
    await Future<void>.delayed(Duration.zero);
    expect(bridge.handleCounter, 1);
    final shutdown = host.shutdown();
    metadataGate.complete();
    await expectLater(
        pending, throwsA(isA<CoproductInitializationCancelled>()));
    await shutdown;
    expect(bridge.installedAttributes, isNull);
  });
}
