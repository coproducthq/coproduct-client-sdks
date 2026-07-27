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
        startupTimeout: const Duration(seconds: 3),
        cancel: CancellationSignal(),
        clock: () => async.elapsed,
      ).then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(reads, 1);
    });
  });

  test('returns for a non-notReady state without waiting', () {
    for (final s in [ProviderState.retrying, ProviderState.fatal]) {
      fakeAsync((async) {
        var done = false;
        awaitInitialReadiness(
          state: () => s,
          startupTimeout: const Duration(seconds: 3),
          cancel: CancellationSignal(),
          clock: () => async.elapsed,
        ).then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isTrue, reason: '$s should return at once');
      });
    }
  });

  test('returns once the first poll leaves notReady before the timeout', () {
    fakeAsync((async) {
      var current = ProviderState.notReady;
      var done = false;
      awaitInitialReadiness(
        state: () => current,
        startupTimeout: const Duration(seconds: 3),
        cancel: CancellationSignal(),
        clock: () => async.elapsed,
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
        startupTimeout: const Duration(milliseconds: 3010),
        cancel: CancellationSignal(),
        clock: () => async.elapsed,
      ).then((_) => done = true);
      async.elapse(const Duration(milliseconds: 3000));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 10)); // exactly the deadline
      expect(done, isTrue);
    });
  });

  test('an already-cancelled signal throws even when the provider is ready', () {
    fakeAsync((async) {
      final cancel = CancellationSignal()..cancel();
      Object? error;
      awaitInitialReadiness(
        state: () => ProviderState.ready,
        startupTimeout: const Duration(seconds: 3),
        cancel: cancel,
        clock: () => async.elapsed,
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
        startupTimeout: const Duration(seconds: 3),
        cancel: cancel,
        clock: () => async.elapsed,
      ).then<void>((_) {}, onError: (Object e, StackTrace _) => error = e);
      async.elapse(const Duration(milliseconds: 200));
      expect(error, isNull);
      cancel.cancel();
      async.flushMicrotasks();
      expect(error, isA<CoproductInitializationCancelled>());
    });
  });
}
