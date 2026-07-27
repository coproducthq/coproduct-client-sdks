import 'dart:async';

import 'cancellation.dart';
import 'errors.dart';
import 'provider_state.dart';

/// The cadence at which readiness re-reads the provider state while it waits,
/// short enough to return promptly once the first poll lands, coarse enough not
/// to spin
const Duration _readinessReadInterval = Duration(milliseconds: 25);

/// Waits until the provider leaves [ProviderState.notReady] or the monotonic
/// [startupTimeout] elapses, whichever comes first. Returns at once when the
/// provider is already off notReady, for example Ready from a cached snapshot. A
/// cancelled [cancel] aborts the wait and throws
/// [CoproductInitializationCancelled], checked synchronously before every state
/// read and raced in each wait. Each wait is capped to the remaining deadline, so
/// the total is strictly bounded by [startupTimeout]. It observes [state] and
/// never drives polling, which the scheduler owns. [delay] is the between-read
/// wait, injected only for tests
Future<void> awaitInitialReadiness({
  required ProviderState Function() state,
  required Duration startupTimeout,
  required CancellationSignal cancel,
  Duration Function()? clock,
  Future<void> Function(Duration)? delay,
}) async {
  if (cancel.isCancelled) {
    throw const CoproductInitializationCancelled();
  }
  if (state() != ProviderState.notReady) {
    return;
  }
  final now = clock ?? _stopwatchClock();
  final deadline = now() + startupTimeout;
  final wait = delay ?? (Duration d) => Future<void>.delayed(d);
  while (true) {
    if (cancel.isCancelled) {
      throw const CoproductInitializationCancelled();
    }
    if (state() != ProviderState.notReady) {
      return;
    }
    final remaining = deadline - now();
    if (remaining <= Duration.zero) {
      return;
    }
    final step =
        remaining < _readinessReadInterval ? remaining : _readinessReadInterval;
    // Race the wait against cancellation, so a cancel does not sit out the full
    // step before the loop notices, the loop then re-checks isCancelled
    await Future.any([wait(step), cancel.whenCancelled]);
  }
}

Duration Function() _stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}
