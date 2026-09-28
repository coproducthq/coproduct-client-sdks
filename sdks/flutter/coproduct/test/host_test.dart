import 'dart:async';

import 'package:coproduct/src/config.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/host.dart';
import 'package:coproduct/src/http_transport.dart';
import 'package:coproduct/src/metadata_collector.dart';
import 'package:coproduct/src/native_bridge.dart';
import 'package:coproduct/src/network_type.dart';
import 'package:coproduct/src/secure_identity_store.dart';
import 'package:coproduct/src/serial_queue.dart';
import 'package:coproduct/src/session.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

const _key = 'cpk_mob_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _sessionPair = SessionPair(firstSeenAt: 1767225600, sessionCount: 3);

/// Completes synchronously, so the pair is settled by the time the batch is
/// assembled and tests that are not about the session see it in the batch
/// rather than as a stray late upsert
Future<SessionPair> _immediateSession() =>
    SynchronousFuture<SessionPair>(_sessionPair);

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
  _RecordingForeground({this.throwsOnBind = false});

  /// Makes the binder throw instead of binding, so a test can cover a binder
  /// that fails
  final bool throwsOnBind;
  int binds = 0;
  int disposes = 0;
  void Function()? onForeground;
  ForegroundBinder get binder => (callback) {
        binds++;
        if (throwsOnBind) throw StateError('bind failed');
        onForeground = callback;
        return () => disposes++;
      };
}

/// A network source that never reports, for tests not about the network. It
/// neither errors nor ends, so it schedules no retries
Stream<Object?> _silentNetwork(int epoch) =>
    StreamController<Object?>.broadcast().stream;

/// One listen the host's network service opened, and its controller
class _NetworkListen {
  _NetworkListen(this.epoch, this.controller);
  final int epoch;
  final StreamController<Object?> controller;

  void emit(String value) =>
      controller.add({'epoch': epoch, 'value': value});
}

/// Stands in for the platform event channel, recording listens and cancels.
/// Broadcast, like the channel's event stream
class _FakeNetworkEvents {
  final List<_NetworkListen> listens = [];
  int cancels = 0;

  Stream<Object?> call(int epoch) {
    final controller =
        StreamController<Object?>.broadcast(onCancel: () => cancels++);
    listens.add(_NetworkListen(epoch, controller));
    return controller.stream;
  }

  _NetworkListen get latest => listens.last;
  int get live => listens.where((l) => l.controller.hasListener).length;
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
  // A late write alongside the handle id it targeted, so a test can tell
  // which runtime generation a write was aimed at
  final List<({int handleId, Map<String, frb.FrbContextValue> attributes})>
      lateWrites = [];
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
      lateWrites.add((handleId: handle.id, attributes: attributes));
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
  Future<SessionPair> Function()? beginSession,
  NetworkTypeEvents? networkTypeEvents,
  _RecordingForeground? networkResume,
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
    beginSession: beginSession ?? _immediateSession,
    initClock: initClock,
    networkTypeEvents: networkTypeEvents ?? _silentNetwork,
    bindNetworkResume: networkResume?.binder ?? (onResume) => null,
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

    test('a throwing error reporter does not fail an exhausted budget either',
        () async {
      // The exhausted-budget path starts its providers without awaiting them, so
      // a reporter that throws there has no caller to surface through. The
      // collector's per-field handling is what absorbs it
      final host = _host(
        _FakeBridge(),
        providers:
            _providers(deviceType: () => throw const HostContextUnavailable()),
        reportError: (_, _) => throw StateError('reporter exploded'),
      );
      await host.initialize(
          sdkKey: _key,
          config: const CoproductConfig(startupTimeout: Duration(milliseconds: 1)));
      await pumpEventQueue();
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
      beginSession: _immediateSession,
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
      networkTypeEvents: _silentNetwork,
      bindNetworkResume: (onResume) => null,
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
    var begun = 0;
    final host = _host(bridge, beginSession: () {
      begun++;
      return _immediateSession();
    });

    final a = host.initialize(sdkKey: 'cpk_mob_a');
    final b = host.initialize(sdkKey: 'cpk_mob_a');
    final ca = await a;
    final cb = await b;
    expect(identical(ca, cb), isTrue);
    expect(begun, 1); // one session transaction for the joined build
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
      beginSession: _immediateSession,
      userAgent: 'coproduct-flutter/test',
      createTransport: (t) => HttpTransport(client: transport, requestTimeout: t),
      secureStore: SecureIdentityStore(
          backing: _MemoryStore(), operationTimeout: const Duration(seconds: 1)),
      metadataProviders: _providers(),
      createClient: (h, identityQueue) => throw StateError('client boom'),
      bindForeground: foreground.binder,
      reportError: (e, s) {},
      networkTypeEvents: _silentNetwork,
      bindNetworkResume: (onResume) => null,
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

  group('session attributes', () {
    test('the pair is published in the initial batch as numbers', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
      final host = _host(bridge);
      await host.initialize(sdkKey: _key);
      expect(bridge.installedAttributes!['first_seen_at'],
          const frb.FrbContextValue.number(1767225600));
      expect(bridge.installedAttributes!['session_count'],
          const frb.FrbContextValue.number(3));
      expect(bridge.lateAttributes, isEmpty);
      await host.shutdown();
    });

    test('the transaction starts only once the handle exists', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
        ..initGate = Completer<void>();
      final handlesAtStart = <int>[];
      final host = _host(bridge, beginSession: () {
        handlesAtStart.add(bridge.handleCounter);
        return _immediateSession();
      });
      final pending = host.initialize(sdkKey: _key);
      await bridge.initializeEntered.future;
      expect(handlesAtStart, isEmpty, reason: 'no handle, so nothing counted yet');
      bridge.initGate!.complete();
      await pending;
      expect(handlesAtStart, [1], reason: 'exactly once, after the handle');
      await host.shutdown();
    });

    test('a rejected key never counts a session', () async {
      final bridge = _FakeBridge()
        ..initError = const frb.InitError.invalidKeyType(prefix: 'cpk_web_');
      var begun = 0;
      final host = _host(bridge, beginSession: () {
        begun++;
        return _immediateSession();
      });
      await expectLater(host.initialize(sdkKey: _key), throwsA(anything));
      expect(begun, 0);
    });

    test('a background isolate never counts a session', () async {
      var begun = 0;
      final host = _host(_FakeBridge(), isRootIsolate: () => false,
          beginSession: () {
        begun++;
        return _immediateSession();
      });
      await expectLater(host.initialize(sdkKey: _key),
          throwsA(isA<CoproductUnsupportedIsolate>()));
      expect(begun, 0);
    });

    test('a shutdown before the handle exists means no session is counted',
        () async {
      final bridge = _FakeBridge()..initGate = Completer<void>();
      var begun = 0;
      final host = _host(bridge, beginSession: () {
        begun++;
        return _immediateSession();
      });
      final pending = host.initialize(sdkKey: _key);
      await bridge.initializeEntered.future;
      final stopping = host.shutdown();
      bridge.initGate!.complete();
      await expectLater(pending, throwsA(isA<CoproductInitializationCancelled>()));
      await stopping;
      expect(begun, 0);
    });

    test('a pair missing the budget publishes late, both values in one upsert',
        () {
      fakeAsync((async) {
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
        final gate = Completer<SessionPair>();
        final host = _host(bridge,
            initClock: () => async.elapsed, beginSession: () => gate.future);
        var returned = false;
        host
            .initialize(
              sdkKey: _key,
              config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
            )
            .then((_) => returned = true);
        async.elapse(const Duration(seconds: 1));
        expect(returned, isTrue, reason: 'initialize waits only for the budget');
        expect(bridge.installedAttributes!.containsKey('first_seen_at'), isFalse);
        expect(bridge.installedAttributes!.containsKey('session_count'), isFalse);
        gate.complete(_sessionPair);
        async.flushMicrotasks();
        expect(bridge.lateAttributes, [_sessionPair.attributes]);
        host.shutdown();
        async.flushMicrotasks();
      });
    });

    test('a wedged transaction holds neither initialize nor shutdown', () {
      fakeAsync((async) {
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
        final host = _host(bridge,
            initClock: () => async.elapsed,
            beginSession: () => Completer<SessionPair>().future);
        var returned = false;
        var stopped = false;
        host
            .initialize(
              sdkKey: _key,
              config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
            )
            .then((_) => returned = true);
        async.elapse(const Duration(seconds: 1));
        expect(returned, isTrue);
        host.shutdown().then((_) => stopped = true);
        async.elapse(const Duration(seconds: 1));
        expect(stopped, isTrue, reason: 'the transaction never completes');
      });
    });

    test('a shutdown while initialize waits on the transaction cancels it', () {
      fakeAsync((async) {
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
        final host = _host(bridge,
            initClock: () => async.elapsed,
            beginSession: () => Completer<SessionPair>().future);
        Object? thrown;
        var stopped = false;
        host
            .initialize(
              sdkKey: _key,
              config: const CoproductConfig(startupTimeout: Duration(seconds: 10)),
            )
            .catchError((Object error) {
          thrown = error;
          return _FakeClient(_FakeHandle(0), SerialQueue());
        });
        async.elapse(const Duration(milliseconds: 100));
        host.shutdown().then((_) => stopped = true);
        async.elapse(const Duration(milliseconds: 100));
        expect(thrown, isA<CoproductInitializationCancelled>(),
            reason: 'the wait ends on shutdown, not on the ten-second budget');
        expect(stopped, isTrue);
        expect(bridge.setAutoPopulatedCalls, 0,
            reason: 'nothing is published into a runtime being torn down');
      });
    });

    test('a pair completing after shutdown is counted but never published', () {
      fakeAsync((async) {
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
        final gate = Completer<SessionPair>();
        final host = _host(bridge,
            initClock: () => async.elapsed, beginSession: () => gate.future);
        host.initialize(
          sdkKey: _key,
          config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
        );
        async.elapse(const Duration(seconds: 1));
        host.shutdown();
        async.flushMicrotasks();
        gate.complete(_sessionPair);
        async.flushMicrotasks();
        expect(bridge.lateAttributes, isEmpty,
            reason: 'the runtime it belonged to is gone');
      });
    });

    test('a storage failure omits both, reports once, and initializes', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
      final errors = <Object>[];
      final host = _host(bridge,
          reportError: (error, _) => errors.add(error),
          beginSession: () async => throw const SessionAttributesUnavailable(
              SessionAttributesUnavailableCause.storageFailure));
      final client = await host.initialize(sdkKey: _key);
      expect(client, isNotNull);
      expect(bridge.installedAttributes!.containsKey('first_seen_at'), isFalse);
      expect(bridge.installedAttributes!.containsKey('session_count'), isFalse);
      expect(errors, [
        const SessionAttributesUnavailable(
            SessionAttributesUnavailableCause.storageFailure)
      ]);
      expect(errors.single.toString(), isNot(contains(_key)));
      await host.shutdown();
    });

    test('a reporter that throws on a session failure does not fail initialize',
        () async {
      final host = _host(_FakeBridge(stateValue: frb.ProviderState.ready),
          reportError: (_, _) => throw StateError('reporter exploded'),
          beginSession: () async => throw const SessionAttributesUnavailable(
              SessionAttributesUnavailableCause.storageFailure));
      await host.initialize(sdkKey: _key);
      await host.shutdown();
    });

    test('a session failure arriving after shutdown reports nothing', () {
      fakeAsync((async) {
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
        final gate = Completer<void>();
        final errors = <Object>[];
        final host = _host(bridge,
            initClock: () => async.elapsed,
            reportError: (error, _) => errors.add(error),
            beginSession: () async {
              await gate.future;
              throw const SessionAttributesUnavailable(
                  SessionAttributesUnavailableCause.storageFailure);
            });
        host.initialize(
          sdkKey: _key,
          config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
        );
        async.elapse(const Duration(seconds: 1));
        host.shutdown();
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        expect(errors, isEmpty,
            reason: 'a stale failure would read as the next runtime\'s error');
      });
    });

    test('a device type read failing after shutdown reports nothing', () {
      // The device type read can outlive its build too, so the diagnostic it
      // raises is subject to the same staleness rule as the session's
      fakeAsync((async) {
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
        final gate = Completer<void>();
        final errors = <Object>[];
        final host = _host(bridge,
            initClock: () => async.elapsed,
            reportError: (error, _) => errors.add(error),
            providers: _providers(deviceType: () async {
              await gate.future;
              throw const HostContextUnavailable();
            }));
        host.initialize(
          sdkKey: _key,
          config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
        );
        async.elapse(const Duration(seconds: 1));
        host.shutdown();
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        expect(errors, isEmpty,
            reason: 'a stale failure would read as the next runtime\'s error');
      });
    });

    test('an unreachable plugin found after shutdown reports nothing', () {
      fakeAsync((async) {
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
        final gate = Completer<void>();
        final errors = <Object>[];
        final host = _host(bridge,
            initClock: () => async.elapsed,
            reportError: (error, _) => errors.add(error),
            beginSession: () async {
              await gate.future;
              throw const HostContextUnavailable();
            });
        host.initialize(
          sdkKey: _key,
          config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
        );
        async.elapse(const Duration(seconds: 1));
        host.shutdown();
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        expect(errors, isEmpty,
            reason: 'a stale failure would read as the next runtime\'s error');
      });
    });

    test('a late pair never publishes into a runtime whose readiness failed',
        () {
      fakeAsync((async) {
        final bridge = _FakeBridge()..stateThrows = true;
        final gate = Completer<SessionPair>();
        final host = _host(bridge,
            initClock: () => async.elapsed, beginSession: () => gate.future);
        Object? thrown;
        host
            .initialize(
              sdkKey: _key,
              config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
            )
            .catchError((Object error) {
          thrown = error;
          return _FakeClient(_FakeHandle(0), SerialQueue());
        });
        async.elapse(const Duration(seconds: 1));
        expect(thrown, isNotNull, reason: 'readiness failed the build');
        gate.complete(_sessionPair);
        async.flushMicrotasks();
        expect(bridge.lateAttributes, isEmpty,
            reason: 'a failed build opens no gate for a late pair');
      });
    });

    test('the transaction starts even when the budget is already spent', () {
      fakeAsync((async) {
        // The deadline governs how long initialize waits, not whether a
        // session is counted, so a slow cold start must not stop counting
        final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
          ..initGate = Completer<void>();
        var begun = 0;
        final host = _host(bridge, initClock: () => async.elapsed,
            beginSession: () {
          begun++;
          return _immediateSession();
        });
        var returned = false;
        host
            .initialize(
              sdkKey: _key,
              config: const CoproductConfig(startupTimeout: Duration(seconds: 1)),
            )
            .then((_) => returned = true);
        async.elapse(const Duration(seconds: 2));
        bridge.initGate!.complete();
        async.flushMicrotasks();
        expect(returned, isTrue);
        expect(begun, 1);
        expect(bridge.installedAttributes!['session_count'],
            const frb.FrbContextValue.number(3));
        host.shutdown();
        async.flushMicrotasks();
      });
    });

    test('an unreachable plugin reports once when beginSession fails first',
        () async {
      // In a real app the device read can be the slow one, so the session
      // failure arrives first and the device failure must be the duplicate
      final errors = <Object>[];
      final firstReport = Completer<void>();
      final deviceGate = Completer<void>();
      final host = _host(
        _FakeBridge(stateValue: frb.ProviderState.ready),
        providers: _providers(deviceType: () async {
          await deviceGate.future;
          throw const HostContextUnavailable();
        }),
        beginSession: () async => throw const HostContextUnavailable(),
        reportError: (error, _) {
          errors.add(error);
          if (!firstReport.isCompleted) firstReport.complete();
        },
      );
      final pending = host.initialize(
        sdkKey: _key,
        config: const CoproductConfig(startupTimeout: Duration(seconds: 5)),
      );
      await firstReport.future;
      deviceGate.complete();
      await pending;
      await pumpEventQueue();
      expect(errors.whereType<HostContextUnavailable>(), hasLength(1),
          reason: 'one misconfiguration reads as one error in either order');
      await host.shutdown();
    });

    test('an unreachable plugin reports once when both methods fail', () async {
      final errors = <Object>[];
      final host = _host(
        _FakeBridge(stateValue: frb.ProviderState.ready),
        providers:
            _providers(deviceType: () => throw const HostContextUnavailable()),
        beginSession: () async => throw const HostContextUnavailable(),
        reportError: (error, _) => errors.add(error),
      );
      await host.initialize(sdkKey: _key);
      expect(errors.whereType<HostContextUnavailable>(), hasLength(1),
          reason: 'one misconfiguration reads as one error');
      await host.shutdown();
    });

    test('a native side missing only beginSession still reports', () async {
      final errors = <Object>[];
      final host = _host(
        _FakeBridge(stateValue: frb.ProviderState.ready),
        beginSession: () async => throw const HostContextUnavailable(),
        reportError: (error, _) => errors.add(error),
      );
      await host.initialize(sdkKey: _key);
      expect(errors, [const HostContextUnavailable()]);
      await host.shutdown();
    });
  });

  group('network_type', () {
    const wifi = {'network_type': frb.FrbContextValue.string('wifi')};

    test('a value publishes after the initial batch and never in it', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
      final network = _FakeNetworkEvents();
      final host = _host(bridge, networkTypeEvents: network.call);
      await host.initialize(sdkKey: _key);
      expect(network.listens, hasLength(1),
          reason: 'observation starts with the runtime');
      network.latest.emit('wifi');
      await pumpEventQueue();
      expect(bridge.installedAttributes!.containsKey('network_type'), isFalse);
      expect(bridge.lateAttributes, [wifi]);
      await host.shutdown();
    });

    test('a value observed during initialize waits for the initial batch',
        () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
        ..publishGate = Completer<void>();
      final network = _FakeNetworkEvents();
      final host = _host(bridge, networkTypeEvents: network.call);
      final init = host.initialize(sdkKey: _key);
      await bridge.publishEntered.future;
      await pumpEventQueue();
      network.latest.emit('wifi');
      await pumpEventQueue();
      expect(bridge.orderedCalls, isEmpty);
      bridge.publishGate!.complete();
      await init;
      await pumpEventQueue();
      expect(bridge.orderedCalls, ['batch', 'late']);
      expect(bridge.lateAttributes, [wifi]);
      await host.shutdown();
    });

    test('shutdown cancels observation, and a value queued behind identify '
        'when it begins is dropped', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
      final network = _FakeNetworkEvents();
      final host = _host(bridge, networkTypeEvents: network.call);
      final client = await host.initialize(sdkKey: _key);
      final identify = Completer<void>();
      unawaited(client.identify(() => identify.future));
      network.latest.emit('wifi');
      await pumpEventQueue();
      await host.shutdown();
      identify.complete();
      await pumpEventQueue();
      expect(bridge.lateAttributes, isEmpty);
      expect(network.live, 0);
    });

    test('a failed build cancels observation', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready)
        ..publishThrows = true;
      final network = _FakeNetworkEvents();
      final host = _host(bridge, networkTypeEvents: network.call);
      await expectLater(host.initialize(sdkKey: _key), throwsA(anything));
      await pumpEventQueue();
      expect(network.live, 0);
    });

    test('resume resubscribes whether or not polling on foreground is on',
        () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
      final network = _FakeNetworkEvents();
      final foreground = _RecordingForeground();
      final networkResume = _RecordingForeground();
      final host = _host(bridge,
          networkTypeEvents: network.call,
          foreground: foreground,
          networkResume: networkResume);
      await host.initialize(
          sdkKey: _key,
          config: const CoproductConfig(pollOnForeground: false));
      await pumpEventQueue();
      expect(foreground.binds, 0);
      expect(networkResume.binds, 1);
      networkResume.onForeground!();
      await pumpEventQueue();
      expect(network.listens, hasLength(2));
      expect(network.live, 1);
      await host.shutdown();
      expect(networkResume.disposes, 1);
    });

    test('a re-initialized runtime publishes network_type again', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
      final network = _FakeNetworkEvents();
      final host = _host(bridge, networkTypeEvents: network.call);
      await host.initialize(sdkKey: _key);
      network.latest.emit('wifi');
      await pumpEventQueue();
      await host.shutdown();
      await host.initialize(sdkKey: _key);
      await pumpEventQueue();
      network.latest.emit('wifi');
      await pumpEventQueue();
      // _FakeBridge classifies only its first call across the bridge's whole
      // lifetime as the batch, so the second runtime's own initial batch lands
      // here as a 'late' entry too. Scope the assertion to network_type
      expect(
          bridge.lateAttributes.where((a) => a.containsKey('network_type')),
          [wifi, wifi]);
      await host.shutdown();
    });

    test('a missing plugin reads as one error across the device read and '
        'every network resume', () async {
      final errors = <Object>[];
      final networkResume = _RecordingForeground();
      final opened = <int>[];
      final host = _host(
        _FakeBridge(stateValue: frb.ProviderState.ready),
        providers:
            _providers(deviceType: () => throw const HostContextUnavailable()),
        networkTypeEvents: (epoch) {
          opened.add(epoch);
          return Stream<Object?>.error(const HostContextUnavailable())
              .asBroadcastStream();
        },
        networkResume: networkResume,
        reportError: (error, _) => errors.add(error),
      );
      await host.initialize(sdkKey: _key);
      await pumpEventQueue();
      networkResume.onForeground!();
      await pumpEventQueue();
      networkResume.onForeground!();
      await pumpEventQueue();
      expect(errors.whereType<HostContextUnavailable>(), hasLength(1),
          reason: 'one misconfiguration reads as one error');
      expect(opened, hasLength(1), reason: 'a resume opens no new listen');
      await host.shutdown();
    });

    test('a native side missing only the network channel still reports',
        () async {
      final errors = <Object>[];
      final host = _host(
        _FakeBridge(stateValue: frb.ProviderState.ready),
        networkTypeEvents: (epoch) =>
            Stream<Object?>.error(const HostContextUnavailable())
                .asBroadcastStream(),
        reportError: (error, _) => errors.add(error),
      );
      await host.initialize(sdkKey: _key);
      await pumpEventQueue();
      expect(errors, [const HostContextUnavailable()]);
      await host.shutdown();
    });

    test('a networkResume binder that throws still lets initialize succeed '
        'and reports the error', () async {
      final errors = <Object>[];
      final networkResume = _RecordingForeground(throwsOnBind: true);
      final host = _host(_FakeBridge(stateValue: frb.ProviderState.ready),
          networkResume: networkResume,
          reportError: (error, _) => errors.add(error));

      final client = await host.initialize(sdkKey: _key);
      expect(client, isNotNull);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      await host.shutdown();
    });

    test('a write queued behind identify at shutdown never reaches a '
        'replacement runtime', () async {
      final bridge = _FakeBridge(stateValue: frb.ProviderState.ready);
      final network = _FakeNetworkEvents();
      final host = _host(bridge, networkTypeEvents: network.call);

      final firstClient = await host.initialize(sdkKey: _key);
      final firstHandleId = firstClient.handle.id;
      final gate = Completer<void>();
      unawaited(firstClient.identify(() => gate.future));
      network.latest.emit('wifi');
      await pumpEventQueue();
      await host.shutdown();

      final secondClient = await host.initialize(sdkKey: _key);
      final secondHandleId = secondClient.handle.id;

      gate.complete();
      await pumpEventQueue();

      final networkWrites =
          bridge.lateWrites.where((w) => w.attributes.containsKey('network_type'));
      expect(networkWrites.where((w) => w.handleId == firstHandleId), isEmpty,
          reason: 'the write never reaches the first runtime after shutdown');
      expect(networkWrites.where((w) => w.handleId == secondHandleId), isEmpty,
          reason: 'the first runtime\'s event never reaches the replacement');
      await host.shutdown();
    });

    test('a readiness failure after publication closes observation and '
        'publishes nothing', () async {
      final bridge = _FakeBridge()..stateThrows = true;
      final network = _FakeNetworkEvents();
      final host = _host(bridge, networkTypeEvents: network.call);

      // The matcher attaches to the future immediately, so a rejection that
      // settles during the pump below is never briefly unhandled
      final expectation =
          expectLater(host.initialize(sdkKey: _key), throwsA(anything));
      await pumpEventQueue();
      // Best-effort: emit only if the listen has already started by the time
      // readiness has had a chance to fail
      if (network.listens.isNotEmpty) {
        network.latest.emit('wifi');
      }
      await expectation;
      await pumpEventQueue();

      expect(network.live, 0);
      expect(
          bridge.lateAttributes.where((a) => a.containsKey('network_type')),
          isEmpty);
    });
  });
}
