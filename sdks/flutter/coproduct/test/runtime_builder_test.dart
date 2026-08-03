import 'dart:async';

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
    this.publishGate,
    this.readyGate,
  });
  final String? failAt;
  final String? supersedeAfter;
  final Set<String> throwOnTeardown;
  final bool reporterThrows;
  // Optional gates that park publish or readiness so a test can prove the
  // concurrent wait does not roll back until both operations have settled
  final Completer<void>? publishGate;
  final Completer<void>? readyGate;
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
    if (publishGate != null) await publishGate!.future;
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
    if (readyGate != null) await readyGate!.future;
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
    // The runtime is created and started first, then attribute install and
    // readiness run concurrently, so both are recorded after start
    expect(stages.calls,
        ['init', 'create-runtime', 'start', 'publish', 'ready']);
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

  test('an attribute failure shuts the created runtime down', () async {
    // Publish and readiness overlap, so both are entered before the publish
    // failure surfaces, and the created runtime owns the rollback
    final stages = _Stages(failAt: 'publish');
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls, [
      'init', 'create-runtime', 'start', 'publish', 'ready', 'shutdown-runtime'
    ]);
  });

  test('a supersession after publish shuts the created runtime down', () async {
    final stages = _Stages(supersedeAfter: 'publish');
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls, [
      'init', 'create-runtime', 'start', 'publish', 'ready', 'shutdown-runtime'
    ]);
  });

  test('a createRuntime failure closes the handle and the transport', () async {
    final stages = _Stages(failAt: 'create');
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls,
        ['init', 'create-runtime', 'shutdown-handle', 'dispose-transport']);
  });

  test('a startRuntime failure shuts the created runtime down', () async {
    final stages = _Stages(failAt: 'start');
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls,
        ['init', 'create-runtime', 'start', 'shutdown-runtime']);
  });

  test('a readiness cancellation shuts the runtime down', () async {
    final stages = _Stages(failAt: 'ready');
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls, [
      'init', 'create-runtime', 'start', 'publish', 'ready', 'shutdown-runtime'
    ]);
  });

  test('a supersession after readiness shuts the runtime down', () async {
    final stages = _Stages(supersedeAfter: 'ready');
    await expectLater(
        stages.run(), throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls, [
      'init', 'create-runtime', 'start', 'publish', 'ready', 'shutdown-runtime'
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
    // Before the runtime exists, a createRuntime failure rolls back the handle
    // and the transport, and a handle-shutdown failure must not skip the dispose
    final stages =
        _Stages(failAt: 'create', throwOnTeardown: {'shutdown-handle'});
    await expectLater(stages.run(), throwsA(isA<StateError>()));
    expect(stages.calls,
        ['init', 'create-runtime', 'shutdown-handle', 'dispose-transport']);
    expect(stages.cleanupErrors.single, isA<StateError>());
  });

  test('a throwing cleanup reporter does not shadow the original error', () async {
    final stages = _Stages(
        failAt: 'create',
        throwOnTeardown: {'shutdown-handle'},
        reporterThrows: true);
    // The createRuntime StateError still surfaces, not the reporter's ArgumentError
    await expectLater(
        stages.run(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'create')));
  });

  test('a publish failure waits for readiness to settle before rollback',
      () async {
    // Publish fails at once while readiness is parked. The concurrent wait must
    // not begin teardown until readiness settles, so the rollback cannot run
    // while readiness is still using the handle
    final readyGate = Completer<void>();
    final stages = _Stages(failAt: 'publish', readyGate: readyGate);
    final result = stages.run();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(stages.calls, ['init', 'create-runtime', 'start', 'publish', 'ready']);
    expect(stages.calls, isNot(contains('shutdown-runtime')));

    readyGate.complete();
    await expectLater(result, throwsA(isA<StateError>()));
    expect(stages.calls.last, 'shutdown-runtime');
  });

  test('a readiness failure waits for publish to settle before rollback',
      () async {
    // Readiness fails at once while publish is parked. Teardown must wait for
    // publish to settle, so the created runtime is not shut down while the
    // attribute install is still in flight against the handle
    final publishGate = Completer<void>();
    final stages = _Stages(failAt: 'ready', publishGate: publishGate);
    final result = stages.run();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(stages.calls, ['init', 'create-runtime', 'start', 'publish', 'ready']);
    expect(stages.calls, isNot(contains('shutdown-runtime')));

    publishGate.complete();
    await expectLater(
        result, throwsA(isA<CoproductInitializationCancelled>()));
    expect(stages.calls.last, 'shutdown-runtime');
  });
}
