import 'dart:async';

import 'package:coproduct/src/cancellation.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/provider_state.dart';
import 'package:coproduct/src/readiness.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns immediately when already ready from cache', () {
    fakeAsync((async) {
      var reads = 0;
      var done = false;
      awaitInitialReadiness(
        state: () {
          reads++;
          return ProviderState.ready;
        },
        deadline: const Duration(seconds: 5),
        clock: () => async.elapsed,
        cancel: CancellationSignal(),
      ).then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(reads, 1);
    });
  });

  test('returns for any non-notReady state without waiting', () {
    for (final s in [ProviderState.retrying, ProviderState.fatal]) {
      fakeAsync((async) {
        var done = false;
        awaitInitialReadiness(
          state: () => s,
          deadline: const Duration(seconds: 5),
          clock: () => async.elapsed,
          cancel: CancellationSignal(),
        ).then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isTrue, reason: '$s should return at once');
      });
    }
  });

  test('returns once the provider leaves notReady before the deadline', () {
    fakeAsync((async) {
      var current = ProviderState.notReady;
      var done = false;
      awaitInitialReadiness(
        state: () => current,
        deadline: const Duration(seconds: 3),
        clock: () => async.elapsed,
        cancel: CancellationSignal(),
      ).then((_) => done = true);
      async.elapse(const Duration(milliseconds: 200));
      expect(done, isFalse);
      current = ProviderState.ready;
      async.elapse(const Duration(milliseconds: 200));
      expect(done, isTrue);
    });
  });

  test('is strictly bounded, the last wait is capped to the remaining deadline',
      () {
    fakeAsync((async) {
      var done = false;
      // 3010ms is not a multiple of the 25ms interval, so the final wait must be
      // capped to the 10ms remaining rather than overshooting a full interval
      awaitInitialReadiness(
        state: () => ProviderState.notReady,
        deadline: const Duration(milliseconds: 3010),
        clock: () => async.elapsed,
        cancel: CancellationSignal(),
      ).then((_) => done = true);
      async.elapse(const Duration(milliseconds: 3000));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 10)); // exactly the deadline
      expect(done, isTrue);
    });
  });

  test('a provider turning ready at the deadline is read, not timed out', () {
    fakeAsync((async) {
      var ready = false;
      var readyReads = 0;
      // The flip is scheduled for the exact deadline instant, so the final state
      // read must observe ready, and counting reads while ready proves the state
      // was read at the boundary rather than the wait ending on plain expiry
      Timer(const Duration(milliseconds: 100), () => ready = true);
      awaitInitialReadiness(
        state: () {
          if (ready) readyReads++;
          return ready ? ProviderState.ready : ProviderState.notReady;
        },
        deadline: const Duration(milliseconds: 100),
        clock: () => async.elapsed,
        cancel: CancellationSignal(),
      );
      async.elapse(const Duration(milliseconds: 100));
      expect(readyReads, greaterThan(0));
    });
  });

  test('an already-cancelled signal throws even when the provider is ready', () {
    fakeAsync((async) {
      final cancel = CancellationSignal()..cancel();
      Object? error;
      awaitInitialReadiness(
        state: () => ProviderState.ready,
        deadline: const Duration(seconds: 5),
        clock: () => async.elapsed,
        cancel: cancel,
      ).then<void>((_) {}, onError: (Object e, StackTrace _) => error = e);
      async.flushMicrotasks();
      expect(error, isA<CoproductInitializationCancelled>());
    });
  });

  test('a cancellation during the wait throws promptly', () {
    fakeAsync((async) {
      final cancel = CancellationSignal();
      Object? error;
      awaitInitialReadiness(
        state: () => ProviderState.notReady,
        deadline: const Duration(seconds: 3),
        clock: () => async.elapsed,
        cancel: cancel,
      ).then<void>((_) {}, onError: (Object e, StackTrace _) => error = e);
      async.elapse(const Duration(milliseconds: 200));
      expect(error, isNull);
      cancel.cancel();
      async.flushMicrotasks();
      expect(error, isA<CoproductInitializationCancelled>());
      // Drain the losing Future.delayed that cancellation raced but cannot cancel
      async.elapse(const Duration(milliseconds: 25));
      async.flushMicrotasks();
    });
  });
}
