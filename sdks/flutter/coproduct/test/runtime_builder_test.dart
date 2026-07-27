import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/runtime_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the build and teardown calls so ordering and rollback are observable.
/// [failAt] names the stage that throws, [supersedeAfter] the stage after which
/// isCurrent turns false, [throwOnTeardown] the teardown seams that fail
class _Stages {
  _Stages({
    this.failAt,
    this.supersedeAfter,
    this.throwOnTeardown = const {},
    this.reporterThrows = false,
  });
  final String? failAt;
  final String? supersedeAfter;
  final Set<String> throwOnTeardown;
  final bool reporterThrows;
  final List<String> calls = [];
  final List<Object> cleanupErrors = [];
  bool current = true;

  void _maybeSupersede(String stage) {
    if (supersedeAfter == stage) current = false;
  }

  Future<String> initHandle() async {
    calls.add('init');
    if (failAt == 'init') throw StateError('init');
    _maybeSupersede('init');
    return 'handle';
  }

  Future<void> disposeTransport() async {
    calls.add('dispose-transport');
    if (throwOnTeardown.contains('dispose-transport')) {
      throw StateError('dispose-transport');
    }
  }

  Future<void> shutdownHandle(String h) async {
    calls.add('shutdown-handle');
    if (throwOnTeardown.contains('shutdown-handle')) {
      throw StateError('shutdown-handle');
    }
  }

  Future<void> publishAttributes(String h) async {
    calls.add('publish');
    if (failAt == 'publish') throw StateError('publish');
    _maybeSupersede('publish');
  }

  String createRuntime(String h) {
    calls.add('create-runtime');
    if (failAt == 'create') throw StateError('create');
    return 'runtime';
  }

  void startRuntime(String r) {
    calls.add('start');
    if (failAt == 'start') throw StateError('start');
  }

  Future<void> shutdownRuntime(String r) async {
    calls.add('shutdown-runtime');
    if (throwOnTeardown.contains('shutdown-runtime')) {
      throw StateError('shutdown-runtime');
    }
  }

  Future<void> awaitReady(String h) async {
    calls.add('ready');
    if (failAt == 'ready') throw const CoproductInitializationCancelled();
    _maybeSupersede('ready');
  }

  Future<String> run() => buildRuntime<String, String>(
        initHandle: initHandle,
        disposeTransport: disposeTransport,
        shutdownHandle: shutdownHandle,
        publishAttributes: publishAttributes,
        createRuntime: createRuntime,
        startRuntime: startRuntime,
        shutdownRuntime: shutdownRuntime,
        awaitReady: awaitReady,
        isCurrent: () => current,
        onCleanupError: (e, s) {
          cleanupErrors.add(e);
          // A distinct type from the seams' StateError so a test can tell the
          // primary failure apart from a reporter failure that leaked
          if (reporterThrows) throw ArgumentError('reporter');
        },
      );
}

void main() {
  test('the happy path builds in order and returns the runtime', () async {
    final stages = _Stages();
    expect(await stages.run(), 'runtime');
    expect(stages.calls,
        ['init', 'publish', 'create-runtime', 'start', 'ready']);
  });

  test('a handle init failure disposes only the transport', () async {
    final stages = _Stages(failAt: 'init');
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls, ['init', 'dispose-transport']);
  });

  test('a supersession after init closes the handle and the transport', () async {
    final stages = _Stages(supersedeAfter: 'init');
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls, ['init', 'shutdown-handle', 'dispose-transport']);
  });

  test('an attribute failure closes the handle then the transport', () async {
    final stages = _Stages(failAt: 'publish');
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls,
        ['init', 'publish', 'shutdown-handle', 'dispose-transport']);
  });

  test('a supersession after publish closes the handle and the transport',
      () async {
    final stages = _Stages(supersedeAfter: 'publish');
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls,
        ['init', 'publish', 'shutdown-handle', 'dispose-transport']);
  });

  test('a createRuntime failure closes the handle and the transport', () async {
    final stages = _Stages(failAt: 'create');
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls,
        ['init', 'publish', 'create-runtime', 'shutdown-handle', 'dispose-transport']);
  });

  test('a startRuntime failure shuts the created runtime down', () async {
    final stages = _Stages(failAt: 'start');
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls,
        ['init', 'publish', 'create-runtime', 'start', 'shutdown-runtime']);
  });

  test('a readiness cancellation shuts the runtime down', () async {
    final stages = _Stages(failAt: 'ready');
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls, [
      'init', 'publish', 'create-runtime', 'start', 'ready', 'shutdown-runtime'
    ]);
  });

  test('a supersession after readiness shuts the runtime down', () async {
    final stages = _Stages(supersedeAfter: 'ready');
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls, [
      'init', 'publish', 'create-runtime', 'start', 'ready', 'shutdown-runtime'
    ]);
  });

  test('a teardown failure during rollback does not shadow the original error',
      () async {
    final stages =
        _Stages(failAt: 'ready', throwOnTeardown: {'shutdown-runtime'});
    // The readiness cancellation still surfaces, not the teardown StateError
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.cleanupErrors.single, isA<StateError>()); // reported, not thrown
  });

  test('a handle-shutdown failure still disposes the transport', () async {
    final stages =
        _Stages(failAt: 'publish', throwOnTeardown: {'shutdown-handle'});
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    // Both cleanups were attempted despite the handle-shutdown failure
    expect(stages.calls,
        ['init', 'publish', 'shutdown-handle', 'dispose-transport']);
    expect(stages.cleanupErrors.single, isA<StateError>());
  });

  test('a throwing cleanup reporter does not shadow the original error', () async {
    final stages = _Stages(
        failAt: 'publish',
        throwOnTeardown: {'shutdown-handle'},
        reporterThrows: true);
    // The publish StateError still surfaces, not the reporter's ArgumentError
    await expectLater(
        stages.run(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'publish')));
  });
}
