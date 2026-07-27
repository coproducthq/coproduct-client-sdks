import 'dart:async';

import 'package:coproduct/src/cancellation.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient {
  _FakeClient(this.id);
  final String id;
}

CoproductManager<_FakeClient> _manager(List<String> log,
        {Future<void> Function(_FakeClient)? shutdownClient,
        void Function(Object, StackTrace)? onCleanupError}) =>
    CoproductManager<_FakeClient>(
      shutdownClient: shutdownClient ?? (c) async => log.add('shutdown-${c.id}'),
      onCleanupError: onCleanupError ?? (_, _) {},
    );

void main() {
  test('two concurrent callers join one gated in-flight build', () async {
    final manager = _manager([]);
    final gate = Completer<_FakeClient>();
    var builds = 0;
    Future<_FakeClient> build(int gen, CancellationSignal cancel, bool Function() isCurrent) {
      builds++;
      return gate.future;
    }

    final a = manager.initialize('k', build);
    final b = manager.initialize('k', build);
    gate.complete(_FakeClient('a'));
    expect(identical(await a, await b), isTrue);
    expect(builds, 1);
  });

  test('a mismatching identity is rejected while a build is in flight', () async {
    final manager = _manager([]);
    final gate = Completer<_FakeClient>();
    manager.initialize('k', (gen, cancel, isCurrent) => gate.future);
    await expectLater(
        manager.initialize('other', (gen, cancel, isCurrent) async => _FakeClient('x')),
        throwsA(isA<CoproductAlreadyInitialized>()));
    gate.complete(_FakeClient('k'));
  });

  test('a completed client is joined on a match and a mismatch is rejected',
      () async {
    final manager = _manager([]);
    final first =
        await manager.initialize('k', (gen, cancel, isCurrent) async => _FakeClient('a'));
    var builds = 0;
    final again = await manager.initialize('k', (gen, cancel, isCurrent) async {
      builds++;
      return _FakeClient('b');
    });
    expect(identical(first, again), isTrue);
    expect(builds, 0); // the completed client was joined, no rebuild
    await expectLater(
        manager.initialize('other', (gen, cancel, isCurrent) async => _FakeClient('c')),
        throwsA(isA<CoproductAlreadyInitialized>()));
  });

  test('the assigned generation is passed to the build and advances', () async {
    final manager = _manager([]);
    expect(manager.generation, 0);
    int? seen;
    await manager.initialize('a', (gen, cancel, isCurrent) async {
      seen = gen;
      return _FakeClient('a');
    });
    expect(seen, 1);
    expect(manager.generation, 1);
    await manager.shutdown();
    expect(manager.generation, 2);
  });

  test('a failed build clears the claim so a retry can proceed, same error',
      () async {
    final manager = _manager([]);
    final err = StateError('boom');
    final first = manager.initialize('k', (gen, cancel, isCurrent) async => throw err);
    final joined = manager.initialize('k', (gen, cancel, isCurrent) async => _FakeClient('x'));
    // The joined caller sees the same error object
    await expectLater(first, throwsA(same(err)));
    await expectLater(joined, throwsA(same(err)));
    final retry =
        await manager.initialize('k2', (gen, cancel, isCurrent) async => _FakeClient('ok'));
    expect(retry.id, 'ok');
  });

  test('shutdown cancels an in-flight init and joined callers see cancellation',
      () async {
    final manager = _manager([]);
    Future<_FakeClient> build(int gen, CancellationSignal cancel, bool Function() isCurrent) async {
      await cancel.whenCancelled;
      throw const CoproductInitializationCancelled();
    }

    final first = manager.initialize('k', build);
    final joined = manager.initialize('k', build);
    final firstErr =
        expectLater(first, throwsA(isA<CoproductInitializationCancelled>()));
    final joinedErr =
        expectLater(joined, throwsA(isA<CoproductInitializationCancelled>()));
    await manager.shutdown();
    await firstErr;
    await joinedErr;
  });

  test('a fresh initialize waits out an in-progress shutdown', () async {
    final teardown = Completer<void>();
    final manager = _manager([], shutdownClient: (c) => teardown.future);
    await manager.initialize('a', (gen, cancel, isCurrent) async => _FakeClient('a'));
    final shuttingDown = manager.shutdown();
    var built = false;
    final next = manager.initialize('b', (gen, cancel, isCurrent) async {
      built = true;
      return _FakeClient('b');
    });
    await Future<void>.delayed(Duration.zero);
    expect(built, isFalse);
    teardown.complete();
    await shuttingDown;
    expect((await next).id, 'b');
    expect(built, isTrue);
  });

  test('a late build completing after a shutdown does not become current',
      () async {
    final manager = _manager([]);
    final release = Completer<_FakeClient>();
    final late = manager.initialize('k', (gen, cancel, isCurrent) async {
      final client = await release.future;
      if (!isCurrent()) throw const CoproductInitializationCancelled();
      return client;
    });
    final lateErr =
        expectLater(late, throwsA(isA<CoproductInitializationCancelled>()));
    final shuttingDown = manager.shutdown();
    await Future<void>.delayed(Duration.zero);
    release.complete(_FakeClient('late'));
    await shuttingDown;
    await lateErr;
    final fresh =
        await manager.initialize('k', (gen, cancel, isCurrent) async => _FakeClient('fresh'));
    expect(fresh.id, 'fresh');
  });

  test('shutdown before init is a no-op, then init and a real shutdown work',
      () async {
    final log = <String>[];
    final manager = _manager(log);
    await manager.shutdown(); // nothing live, no-op, no generation bump
    expect(manager.generation, 0);
    await manager.initialize('a', (gen, cancel, isCurrent) async => _FakeClient('a'));
    await manager.shutdown(); // tears the real client down
    expect(log, ['shutdown-a']);
  });

  test('a concurrent second shutdown joins the first', () async {
    final log = <String>[];
    final gate = Completer<void>();
    final manager = _manager(log, shutdownClient: (c) async {
      await gate.future;
      log.add('shutdown-${c.id}');
    });
    await manager.initialize('a', (gen, cancel, isCurrent) async => _FakeClient('a'));
    final first = manager.shutdown();
    final second = manager.shutdown();
    gate.complete();
    await Future.wait([first, second]);
    expect(log.where((e) => e == 'shutdown-a').length, 1);
  });

  test('a synchronously throwing build is handled like an async failure',
      () async {
    final manager = _manager([]);
    final err = StateError('sync boom');
    // A non-async closure that throws synchronously, not a rejected future
    await expectLater(
        manager.initialize('k', (gen, cancel, isCurrent) => throw err),
        throwsA(same(err)));
    final retry =
        await manager.initialize('k2', (gen, cancel, isCurrent) async => _FakeClient('ok'));
    expect(retry.id, 'ok');
  });

  test('a build that fails after being superseded reports cancellation', () async {
    final manager = _manager([]);
    final proceed = Completer<void>();
    // A build that does not observe cancel, then throws a distinct raw error
    // only after a shutdown has superseded its generation
    Future<_FakeClient> build(int gen, CancellationSignal cancel, bool Function() isCurrent) async {
      await proceed.future;
      throw StateError('bridge error');
    }

    final first = manager.initialize('k', build);
    final joined = manager.initialize('k', build);
    final firstErr =
        expectLater(first, throwsA(isA<CoproductInitializationCancelled>()));
    final joinedErr =
        expectLater(joined, throwsA(isA<CoproductInitializationCancelled>()));
    final shuttingDown = manager.shutdown();
    await Future<void>.delayed(Duration.zero);
    proceed.complete(); // the build now throws, but its generation is superseded
    await shuttingDown;
    await firstErr;
    await joinedErr;
  });

  test('a superseded build that returned a client tears the orphan down once and reports a teardown failure',
      () async {
    var teardowns = 0;
    Object? reported;
    final manager = _manager([],
        shutdownClient: (c) async {
          teardowns++;
          throw StateError('td');
        },
        onCleanupError: (e, _) => reported = e);
    final release = Completer<_FakeClient>();
    // Returns a client despite supersession, so the manager tears the orphan down
    final late = manager.initialize('k', (gen, cancel, isCurrent) => release.future);
    final lateErr =
        expectLater(late, throwsA(isA<CoproductInitializationCancelled>()));
    final shuttingDown = manager.shutdown();
    await Future<void>.delayed(Duration.zero);
    release.complete(_FakeClient('orphan'));
    await shuttingDown;
    await lateErr;
    expect(teardowns, 1); // the orphan was torn down exactly once
    expect(reported, isA<StateError>()); // the teardown failure was reported
  });

  test('a throwing cleanup reporter does not shadow the orphan cancellation',
      () async {
    final manager = _manager([],
        shutdownClient: (c) async => throw StateError('td'),
        onCleanupError: (e, s) => throw ArgumentError('reporter'));
    final release = Completer<_FakeClient>();
    // Returns a client despite supersession, the teardown throws, and the
    // reporter throws too, yet the caller still sees cancellation
    final late = manager.initialize('k', (gen, cancel, isCurrent) => release.future);
    final lateErr =
        expectLater(late, throwsA(isA<CoproductInitializationCancelled>()));
    final shuttingDown = manager.shutdown();
    await Future<void>.delayed(Duration.zero);
    release.complete(_FakeClient('orphan'));
    await shuttingDown;
    await lateErr;
  });
}
