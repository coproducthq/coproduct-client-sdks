import 'dart:async';

import 'package:coproduct/src/config.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/host.dart';
import 'package:coproduct/src/host_context_channel.dart';
import 'package:coproduct/src/http_transport.dart';
import 'package:coproduct/src/metadata_collector.dart';
import 'package:coproduct/src/native_bridge.dart';
import 'package:coproduct/src/secure_identity_store.dart';
import 'package:coproduct/src/serial_queue.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

const _key = 'cpk_mob_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// A stand-in for the opaque FRB handle, one per fake initialize.
class _FakeHandle {
  _FakeHandle(this.id);
  final int id;
}

/// The caller-facing client the host returns in tests, carrying its handle so a
/// test can assert which handle was wrapped.
class _FakeClient {
  _FakeClient(this.handle, this.identityQueue);
  final _FakeHandle handle;
  final SerialQueue identityQueue;

  /// Stands in for an identity mutator: what matters is that it occupies the
  /// same queue the auto-upsert path uses, so ordering can be observed
  Future<void> identify(Future<void> Function() body) =>
      identityQueue.add(body);
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

  final List<String> orderedCalls = [];
  final List<Map<String, frb.FrbContextValue>> lateAttributes = [];
  int setAutoPopulatedCalls = 0;
  Completer<void>? publishGate; // suspends the initial publication
  final Completer<void> publishEntered = Completer<void>(); // entry handshake
  bool stateThrows = false; // makes the injected readiness state closure throw

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
    setAutoPopulatedCalls++;
    final isBatch = setAutoPopulatedCalls == 1;
    if (!publishEntered.isCompleted) publishEntered.complete();
    if (publishGate != null) await publishGate!.future;
    orderedCalls.add(isBatch ? 'batch' : 'late');
    if (isBatch) {
      attributesInstalledAtClientCount = clientsCreated;
      installedAttributes = attributes;
    } else {
      lateAttributes.add(attributes);
    }
    if (publishThrows) throw StateError('publish failed');
  }

  int stateReads = 0;
  final Completer<void> stateRead = Completer<void>();

  @override
  frb.ProviderState state(_FakeHandle handle) {
    if (stateThrows) throw StateError('state read failed');
    stateReads++;
    if (!stateRead.isCompleted) stateRead.complete();
    return stateValue;
  }

  Completer<void>? pollGate; // suspends the first poll in flight
  final Completer<void> pollEntered = Completer<void>();
  bool pollFinished = false;

  @override
  Future<frb.PollOutcome> pollNow(_FakeHandle handle) async {
    pollCalls++;
    if (!pollEntered.isCompleted) pollEntered.complete();
    if (!firstPoll.isCompleted) firstPoll.complete();
    if (pollGate != null) await pollGate!.future;
    pollFinished = true;
    return const frb.PollOutcome.updated();
  }

  @override
  Future<void> shutdown(_FakeHandle handle) async => shutdownCalls++;
}

/// Metadata providers returning a fixed value per field.
MetadataProviders _providers({
  MetadataProvider? timezone,
  MetadataProvider? deviceType,
}) =>
    MetadataProviders(
      deviceType: deviceType ?? stringProvider(() async => 'phone'),
      platform: stringProvider(() async => 'android'),
      osVersion: stringProvider(() async => '14'),
      appVersion: stringProvider(() async => '1.2.3'),
      appBuild: stringProvider(() async => '42'),
      locale: stringProvider(() async => 'en-US'),
      timezone: timezone ?? stringProvider(() async => 'America/New_York'),
    );

CoproductHost<_FakeHandle, _FakeClient> _host(
  _FakeBridge bridge, {
  _MemoryStore? store,
  MetadataProviders? providers,
  http.Client? transportClient,
  _RecordingForeground? foreground,
  Duration Function()? initClock,
  bool Function()? isRootIsolate,
  void Function(Object error, StackTrace stack)? reportError,
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
    createClient: (h, identityQueue) {
      bridge.clientsCreated++;
      return _FakeClient(h, identityQueue);
    },
    bindForeground: foreground?.binder ?? (onForeground) => null,
    reportError: reportError ?? (e, s) {},
    isRootIsolate: isRootIsolate ?? () => true,
    initClock: initClock,
  );
}

void main() {
  group('host context diagnostics', () {
    test('an unreachable host-context plugin reports once and still initializes',
        () async {
      final errors = <Object>[];
      final host = _host(
        _FakeBridge(),
        providers:
            _providers(deviceType: () => throw const HostContextUnavailable()),
        reportError: (error, _) => errors.add(error),
      );

      final client = await host.initialize(sdkKey: _key);
      expect(client, isNotNull, reason: 'flag evaluation is unaffected');
      expect(errors.whereType<HostContextUnavailable>(), hasLength(1),
          reason: 'release visible, and exactly once per initialization');
      expect(errors.single.toString(), isNot(contains(_key)));
      await host.shutdown();
    });

    test('a device that declines to classify itself reports nothing', () async {
      final errors = <Object>[];
      final host = _host(
        _FakeBridge(),
        providers: _providers(deviceType: () async => null),
        reportError: (error, _) => errors.add(error),
      );

      await host.initialize(sdkKey: _key);
      expect(errors, isEmpty,
          reason: 'an omitted value is a device fact, not a misconfiguration');
      await host.shutdown();
    });

    test('a throwing error reporter does not fail initialization', () async {
      final host = _host(
        _FakeBridge(),
        providers:
            _providers(deviceType: () => throw const HostContextUnavailable()),
        reportError: (_, _) => throw StateError('reporter exploded'),
      );
      await host.initialize(sdkKey: _key);
      await host.shutdown();
    });
  });

  group('late publication', () {
    const shortBudget =
        CoproductConfig(startupTimeout: Duration(milliseconds: 50));

    test('a late provider publishes after the initial batch, in order',
        () async {
      final bridge = _FakeBridge();
      final completer = Completer<frb.FrbContextValue?>();
      final host =
          _host(bridge, providers: _providers(timezone: () => completer.future));

      await host.initialize(sdkKey: _key, config: shortBudget);
      expect(bridge.installedAttributes!.containsKey('timezone'), isFalse);
      expect(bridge.setAutoPopulatedCalls, 1);

      completer.complete(const frb.FrbContextValue.string('UTC'));
      await pumpEventQueue();

      expect(bridge.setAutoPopulatedCalls, 2);
      expect(bridge.lateAttributes.single['timezone'],
          const frb.FrbContextValue.string('UTC'));
      await host.shutdown();
    });

    test('a late result arriving during the build waits for the initial batch',
        () async {
      final bridge = _FakeBridge()..publishGate = Completer<void>();
      final completer = Completer<frb.FrbContextValue?>();
      final host =
          _host(bridge, providers: _providers(timezone: () => completer.future));

      final init = host.initialize(sdkKey: _key, config: shortBudget);
      // Wait for the publication to be in flight rather than pumping and
      // hoping: on a fast run the value would otherwise join the initial batch
      await bridge.publishEntered.future;
      completer.complete(const frb.FrbContextValue.string('UTC'));
      await pumpEventQueue();
      expect(bridge.orderedCalls, isEmpty, reason: 'nothing published yet');

      bridge.publishGate!.complete();
      await init;
      await pumpEventQueue();

      expect(bridge.orderedCalls, ['batch', 'late'],
          reason: 'a late write must never precede the batch it amends');
      await host.shutdown();
    });

    test('a late result arriving before the handle exists still publishes',
        () async {
      final bridge = _FakeBridge()..initGate = Completer<void>();
      // Settles after the deadline but while the native initialize is still
      // suspended, so it is late and there is no handle to write through yet
      final host = _host(bridge,
          providers: _providers(
              timezone: () => Future<frb.FrbContextValue?>.delayed(
                  const Duration(milliseconds: 40),
                  () => const frb.FrbContextValue.string('UTC'))));

      final init = host.initialize(
          sdkKey: _key,
          config: const CoproductConfig(startupTimeout: Duration(milliseconds: 20)));
      await bridge.initializeEntered.future;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      bridge.initGate!.complete();
      await init;
      await pumpEventQueue();

      expect(bridge.lateAttributes.single['timezone'],
          const frb.FrbContextValue.string('UTC'));
      await host.shutdown();
    });

    test('a late upsert orders behind identity work on the client queue',
        () async {
      final bridge = _FakeBridge();
      final completer = Completer<frb.FrbContextValue?>();
      final host =
          _host(bridge, providers: _providers(timezone: () => completer.future));

      final client = await host.initialize(sdkKey: _key, config: shortBudget);

      final release = Completer<void>();
      final identity = client.identify(() async {
        await release.future;
        bridge.orderedCalls.add('identify');
      });
      completer.complete(const frb.FrbContextValue.string('UTC'));
      await pumpEventQueue();

      release.complete();
      await identity;
      await pumpEventQueue();

      expect(bridge.orderedCalls, ['batch', 'identify', 'late'],
          reason: 'one shared queue is the point, a second would reorder these');
      await host.shutdown();
    });

    test('a late result is dropped when the build fails after publication',
        () async {
      // Publication succeeds, then readiness throws because its injected state
      // closure does. An ordinary build failure does not advance the manager's
      // generation, so only the gate's placement prevents a write to a handle
      // whose runtime was torn down
      final bridge = _FakeBridge()..stateThrows = true;
      final completer = Completer<frb.FrbContextValue?>();
      final host =
          _host(bridge, providers: _providers(timezone: () => completer.future));

      await expectLater(
          host.initialize(sdkKey: _key, config: shortBudget), throwsA(anything));
      completer.complete(const frb.FrbContextValue.string('UTC'));
      await pumpEventQueue();

      expect(bridge.lateAttributes, isEmpty);
    });

    test('a late result is dropped when shutdown supersedes the runtime',
        () async {
      final bridge = _FakeBridge();
      final completer = Completer<frb.FrbContextValue?>();
      final host =
          _host(bridge, providers: _providers(timezone: () => completer.future));

      await host.initialize(sdkKey: _key, config: shortBudget);
      await host.shutdown();
      completer.complete(const frb.FrbContextValue.string('UTC'));
      await pumpEventQueue();

      expect(bridge.lateAttributes, isEmpty);
    });
  });

  group('isolate support', () {
    test('initialize on a non-root isolate is rejected before any native work',
        () async {
      final bridge = _FakeBridge();
      final host = _host(bridge, isRootIsolate: () => false);

      await expectLater(
        host.initialize(sdkKey: _key),
        throwsA(isA<CoproductUnsupportedIsolate>()),
      );

      expect(bridge.ensureInitializedCalls, 0,
          reason: 'the gate must precede native library loading');
      expect(bridge.initializeEntered.isCompleted, isFalse);
    });

    test('a rejected background isolate produces no host-context diagnostic',
        () async {
      final errors = <Object>[];
      final host = _host(_FakeBridge(),
          isRootIsolate: () => false, reportError: (e, _) => errors.add(e));

      await expectLater(
        host.initialize(sdkKey: _key),
        throwsA(isA<CoproductUnsupportedIsolate>()),
      );

      // The two failures are distinct and must stay distinct: an unsupported
      // isolate is a support boundary, an unregistered plugin is a
      // misconfiguration
      expect(errors, isEmpty);
    });

    test('initialize on a root isolate proceeds', () async {
      final host = _host(_FakeBridge(), isRootIsolate: () => true);
      await host.initialize(sdkKey: _key);
      await host.shutdown();
    });
  });

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

  test('auto-populated attributes are installed before initialize returns',
      () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(bridge);

    await host.initialize(sdkKey: 'cpk_mob_a');

    // The install completed before initialize returned, so an immediate read on
    // the returned client sees the automatic context
    expect(bridge.installedAttributes, isNotNull);
    expect(bridge.installedAttributes!['platform'],
        const frb.FrbContextValue.string('android'));
    expect(bridge.installedAttributes!['timezone'],
        const frb.FrbContextValue.string('America/New_York'));

    await host.shutdown();
  });

  test('the first poll overlaps metadata collection', () async {
    // Park a metadata provider and prove the first poll fires while collection
    // is still in flight, so a cold start is max(metadata, network) not their
    // sum. A regression that installed metadata before starting the poll would
    // never complete firstPoll here while the provider is parked
    final metadataGate = Completer<void>();
    final metadataStarted = Completer<void>();
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(
      bridge,
      providers: MetadataProviders(
        deviceType: stringProvider(() async => 'phone'),
        platform: () async {
          if (!metadataStarted.isCompleted) metadataStarted.complete();
          await metadataGate.future;
          return const frb.FrbContextValue.string('android');
        },
        osVersion: stringProvider(() async => '14'),
        appVersion: stringProvider(() async => '1.2.3'),
        appBuild: stringProvider(() async => '42'),
        locale: stringProvider(() async => 'en-US'),
        timezone: stringProvider(() async => 'America/New_York'),
      ),
    );

    final pending = host.initialize(sdkKey: 'cpk_mob_a');
    await metadataStarted.future;
    await bridge.firstPoll.future;
    expect(metadataGate.isCompleted, isFalse);
    metadataGate.complete();
    await pending;
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
        deviceType: stringProvider(() async => 'phone'),
        platform: () async {
          if (!metadataStarted.isCompleted) metadataStarted.complete();
          await metadataGate.future;
          return const frb.FrbContextValue.string('android');
        },
        osVersion: stringProvider(() async => '14'),
        appVersion: stringProvider(() async => '1.2.3'),
        appBuild: stringProvider(() async => '42'),
        locale: stringProvider(() async => 'en-US'),
        timezone: stringProvider(() async => 'America/New_York'),
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
      isRootIsolate: () => true,
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
        deviceType: stringProvider(() async => 'phone'),
        platform: () async {
          if (!metadataStarted.isCompleted) metadataStarted.complete();
          return const frb.FrbContextValue.string('android');
        },
        osVersion: stringProvider(() async => '14'),
        appVersion: stringProvider(() async => '1.2.3'),
        appBuild: stringProvider(() async => '42'),
        locale: stringProvider(() async => 'en-US'),
        timezone: stringProvider(() async => 'America/New_York'),
      ),
      createClient: (h, identityQueue) => _FakeClient(h, identityQueue),
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

    // A non-init error propagates unchanged (translation is narrow). The runtime
    // is created before attributes are published, so the created runtime owns the
    // teardown and shuts down both the core handle and the transport
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
      isRootIsolate: () => true,
      userAgent: 'coproduct-flutter/test',
      createTransport: (t) => HttpTransport(client: transport, requestTimeout: t),
      secureStore: SecureIdentityStore(
          backing: _MemoryStore(), operationTimeout: const Duration(seconds: 1)),
      metadataProviders: _providers(),
      createClient: (h, identityQueue) => throw StateError('client boom'),
      bindForeground: foreground.binder,
      reportError: (e, s) {},
    );

    await expectLater(
        host.initialize(sdkKey: 'cpk_mob_a'), throwsA(isA<StateError>()));
    expect(foreground.binds, 0); // createClient threw before any bind
    expect(bridge.shutdownCalls, greaterThan(0)); // handle shut down
    expect(transport.closed, isTrue); // transport disposed
  });

  test('the deadline is captured before native setup, so it consumes the budget',
      () {
    fakeAsync((async) {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.notReady)
        ..ensureInitializedGate = Completer<void>();
      final host = _host(bridge, initClock: () => async.elapsed);
      var returned = false;
      host
          .initialize(
            sdkKey: 'cpk_mob_a',
            config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
          )
          .then((_) => returned = true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2)); // native load burns the budget
      expect(returned, isFalse, reason: 'still blocked on mandatory native setup');
      bridge.ensureInitializedGate!.complete();
      async.flushMicrotasks();
      expect(returned, isTrue); // no budget remains, so no further wait
      host.shutdown();
      async.flushMicrotasks();
    });
  });

  test('automatic attributes are installed before initialize returns', () async {
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
    final host = _host(bridge);
    await host.initialize(sdkKey: 'cpk_mob_a');
    expect(bridge.installedAttributes!['platform'],
        const frb.FrbContextValue.string('android'));
    await host.shutdown();
  });

  test('native setup consuming part of the budget still delivers attributes', () {
    fakeAsync((async) {
      // Gated native load burns part of a 1s budget, and the immediate providers
      // still fit in the remainder, so the attributes are installed rather than dropped
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
        ..ensureInitializedGate = Completer<void>();
      final host = _host(bridge, initClock: () => async.elapsed);
      host.initialize(
        sdkKey: 'cpk_mob_a',
        config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 400)); // partial budget spent
      bridge.ensureInitializedGate!.complete();
      async.flushMicrotasks();
      expect(bridge.installedAttributes!['platform'],
          const frb.FrbContextValue.string('android'));
      host.shutdown();
      async.flushMicrotasks();
    });
  });

  test('slow metadata and slow readiness share one deadline, not the sum', () {
    fakeAsync((async) {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.notReady);
      var returned = false;
      final host = _host(
        bridge,
        initClock: () => async.elapsed,
        // platform never settles, so metadata rides the deadline
        providers: MetadataProviders(
          deviceType: stringProvider(() async => 'phone'),
          platform: () => Completer<frb.FrbContextValue?>().future,
          osVersion: stringProvider(() async => '14'),
          appVersion: stringProvider(() async => '1.2.3'),
          appBuild: stringProvider(() async => '42'),
          locale: stringProvider(() async => 'en-US'),
          timezone: stringProvider(() async => 'America/New_York'),
        ),
      );
      host
          .initialize(
            sdkKey: 'cpk_mob_a',
            config: const CoproductConfig(startupTimeout: Duration(seconds: 2)),
          )
          .then((_) => returned = true);
      async.elapse(const Duration(milliseconds: 1999));
      expect(returned, isFalse);
      async.elapse(const Duration(milliseconds: 1)); // one shared 2s deadline
      async.flushMicrotasks();
      expect(returned, isTrue); // not 4s (metadata 2s + readiness 2s)
      host.shutdown();
      async.flushMicrotasks();
    });
  });

  test('an in-flight first poll stays scheduler-owned and completes after return',
      () {
    fakeAsync((async) {
      // The first poll is held in flight while readiness times out, so initialize
      // returns NotReady with the poll still running. Releasing it proves the
      // scheduler still owns and completes the poll after initialize returned,
      // rather than abandoning it at the deadline
      final pollGate = Completer<void>();
      final bridge = _FakeBridge(stateValue: frb.ProviderState.notReady)
        ..pollGate = pollGate;
      final host = _host(bridge, initClock: () => async.elapsed);
      var returned = false;
      host
          .initialize(
            sdkKey: 'cpk_mob_a',
            config: const CoproductConfig(startupTimeout: Duration(milliseconds: 100)),
          )
          .then((_) => returned = true);
      async.elapse(const Duration(milliseconds: 100)); // readiness deadline
      async.flushMicrotasks();
      expect(returned, isTrue);
      expect(bridge.pollEntered.isCompleted, isTrue);
      expect(bridge.pollFinished, isFalse); // still in flight at return
      pollGate.complete();
      async.flushMicrotasks();
      expect(bridge.pollFinished, isTrue); // completed after return
      host.shutdown();
      async.flushMicrotasks();
    });
  });

  test('joined callers share one deadline rather than restarting it', () {
    fakeAsync((async) {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.notReady);
      var firstReturned = false;
      var secondReturned = false;
      const config = CoproductConfig(startupTimeout: Duration(seconds: 2));
      final host = _host(bridge, initClock: () => async.elapsed);
      host.initialize(sdkKey: 'cpk_mob_a', config: config)
          .then((_) => firstReturned = true);
      async.elapse(const Duration(seconds: 1)); // first build is 1s in
      host.initialize(sdkKey: 'cpk_mob_a', config: config)
          .then((_) => secondReturned = true);
      async.elapse(const Duration(seconds: 1)); // the original 2s deadline elapses
      async.flushMicrotasks();
      expect(firstReturned, isTrue);
      expect(secondReturned, isTrue); // joined, not restarted at 3s
      host.shutdown();
      async.flushMicrotasks();
    });
  });

  test('a shutdown during metadata collection throws with no unhandled error',
      () async {
    final gate = Completer<frb.FrbContextValue?>();
    final bridge = _FakeBridge(stateValue: frb.ProviderState.notReady);
    final host = _host(
      bridge,
      providers: MetadataProviders(
        deviceType: stringProvider(() async => 'phone'),
        platform: () => gate.future,
        osVersion: stringProvider(() async => '14'),
        appVersion: stringProvider(() async => '1.2.3'),
        appBuild: stringProvider(() async => '42'),
        locale: stringProvider(() async => 'en-US'),
        timezone: stringProvider(() async => 'America/New_York'),
      ),
    );
    final pending = host.initialize(
      sdkKey: 'cpk_mob_a',
      config: const CoproductConfig(startupTimeout: Duration(seconds: 30)),
    );
    await bridge.initializeEntered.future;
    final shutdown = host.shutdown();
    await expectLater(pending, throwsA(isA<CoproductInitializationCancelled>()));
    await shutdown;
    // No unhandled async error: flutter_test would fail this test if the abandoned
    // metadata future's cancellation escaped
  });

  test('metadata cancellation before any handle exists does not leak an error',
      () async {
    // Park in the cache lookup with wedged metadata, then shut down before a handle
    // exists, so the collector is cancelled and abandoned before publishAttributes
    // ever runs. The outcome wrapper must absorb its cancellation. Without the
    // wrapper the collector would throw with no listener and flutter_test would
    // fail this test on the unhandled async error
    final cacheGate = Completer<void>();
    final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
      ..cacheDirectoryGate = cacheGate;
    final host = _host(
      bridge,
      providers: MetadataProviders(
        deviceType: stringProvider(() async => 'phone'),
        platform: () => Completer<frb.FrbContextValue?>().future, // wedged
        osVersion: stringProvider(() async => '14'),
        appVersion: stringProvider(() async => '1.2.3'),
        appBuild: stringProvider(() async => '42'),
        locale: stringProvider(() async => 'en-US'),
        timezone: stringProvider(() async => 'America/New_York'),
      ),
    );
    final pending = host.initialize(
      sdkKey: 'cpk_mob_a',
      config: const CoproductConfig(startupTimeout: Duration(seconds: 30)),
    );
    await bridge.cacheDirectoryEntered.future; // parked in cache lookup, no handle
    final shutdown = host.shutdown(); // bumps generation, cancels synchronously
    cacheGate.complete(); // cache lookup finishes, then isCurrent is false
    await expectLater(pending, throwsA(isA<CoproductInitializationCancelled>()));
    await shutdown;
    expect(bridge.initializeEntered.isCompleted, isFalse); // no handle was built
  });

  test('a shutdown during the readiness wait cancels through the runtime teardown',
      () {
    fakeAsync((async) {
      // State never leaves notReady and the deadline stays ahead, so readiness
      // loops. Gate the shutdown on readiness having actually read state, so the
      // build is proven inside the readiness wait rather than an earlier stage
      final bridge = _FakeBridge(stateValue: frb.ProviderState.notReady);
      final foreground = _RecordingForeground();
      final host = _host(
        bridge,
        foreground: foreground,
        initClock: () => async.elapsed,
      );
      Object? error;
      host
          .initialize(
            sdkKey: 'cpk_mob_a',
            config: const CoproductConfig(startupTimeout: Duration(seconds: 30)),
          )
          .then<void>((_) {}, onError: (Object e, StackTrace _) => error = e);
      async.elapse(const Duration(milliseconds: 50));
      expect(bridge.stateReads, greaterThan(0), reason: 'readiness entered');
      host.shutdown();
      async.flushMicrotasks();
      expect(error, isA<CoproductInitializationCancelled>());
      // Rollback used runtime shutdown, which disposes the foreground listener
      expect(foreground.disposes, greaterThan(0));
      // Drain the readiness step's losing Future.delayed, which cancellation raced
      // but cannot cancel, so no bounded timer is left pending in the fake zone
      async.elapse(const Duration(milliseconds: 25));
      async.flushMicrotasks();
    });
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
        deviceType: stringProvider(() async => 'phone'),
        platform: () async {
          if (!metadataStarted.isCompleted) metadataStarted.complete();
          await metadataGate.future;
          return const frb.FrbContextValue.string('android');
        },
        osVersion: stringProvider(() async => '14'),
        appVersion: stringProvider(() async => '1.2.3'),
        appBuild: stringProvider(() async => '42'),
        locale: stringProvider(() async => 'en-US'),
        timezone: stringProvider(() async => 'America/New_York'),
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
