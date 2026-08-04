import 'dart:async';

import 'cancellation.dart';
import 'errors.dart';
import 'provider_state.dart';

/// The cadence at which readiness re-reads the provider state while it waits,
/// short enough to return promptly once the first poll lands, coarse enough not
/// to spin.
const Duration _readinessReadInterval = Duration(milliseconds: 25);

/// Waits until the provider leaves [ProviderState.notReady] or the shared
/// monotonic [deadline] elapses, whichever comes first, throwing
/// [CoproductInitializationCancelled] if [cancel] fires. Each pass runs in a
/// fixed order so a provider that turns ready at the deadline instant is seen by
/// the final state read rather than lost to expiry: a synchronous cancellation
/// check, then a synchronous state read, then the deadline check. [clock] is the
/// build's shared monotonic clock, so the deadline is measured on the same origin
/// as metadata collection.
Future<void> awaitInitialReadiness({
  required ProviderState Function() state,
  required Duration deadline,
  required Duration Function() clock,
  required CancellationSignal cancel,
}) async {
  while (true) {
    if (cancel.isCancelled) {
      throw const CoproductInitializationCancelled();
    }
    if (state() != ProviderState.notReady) {
      return;
    }
    final remaining = deadline - clock();
    if (remaining <= Duration.zero) {
      return;
    }
    final step =
        remaining < _readinessReadInterval ? remaining : _readinessReadInterval;
    // Race the wait against cancellation so a cancel does not sit out the full
    // step, then the loop re-checks in order
    await Future.any([Future<void>.delayed(step), cancel.whenCancelled]);
  }
}
