import 'dart:async';

import 'rust/api.dart' as frb;

/// The backoff multiplier for a stale provider, matching the iOS host timer
const int _backoffMultiplier = 5;

/// The delay before the next poll for a given outcome. A null result stops
/// polling. A rate limit honors the server retry-after but never polls faster
/// than the normal interval. Retrying and deduped stay at normal cadence, only a
/// stale provider backs off, and a fatal provider is terminal
Duration? nextPollDelay(frb.PollOutcome outcome, Duration interval) =>
    switch (outcome) {
      frb.PollOutcome_Updated() ||
      frb.PollOutcome_NotModified() ||
      frb.PollOutcome_Retrying() ||
      frb.PollOutcome_DedupedSkipped() =>
        interval,
      frb.PollOutcome_RateLimited(:final retryAfterSecs) =>
        Duration(seconds: retryAfterSecs) > interval
            ? Duration(seconds: retryAfterSecs)
            : interval,
      frb.PollOutcome_Stale() => interval * _backoffMultiplier,
      frb.PollOutcome_Fatal() => null,
    };

/// Whether an outcome opens a back-off window a foreground event must wait out
/// rather than bypass. Retrying is normal cadence, so a foreground refreshes
/// during it
bool _isBackoff(frb.PollOutcome outcome) =>
    outcome is frb.PollOutcome_RateLimited || outcome is frb.PollOutcome_Stale;

/// Runs the poll on a one-shot self-rescheduling timer. Polls immediately on
/// start, never overlaps a poll, reschedules from each outcome, refreshes on
/// foreground without shortening an active back-off, and stops on a fatal outcome
/// or shutdown. Not Timer.periodic, the next timer is armed only after the prior
/// poll settles
class Scheduler {
  Scheduler({
    required this.poll,
    required this.interval,
    required this.pollOnForeground,
    required void Function(Object error, StackTrace stack) onError,
    Duration Function()? clock,
  })  : _now = clock ?? _monotonicClock(),
        // ignore: prefer_initializing_formals
        _onError = onError;

  final Future<frb.PollOutcome> Function() poll;
  final Duration interval;
  final bool pollOnForeground;

  // Injectable monotonic elapsed source and required diagnostic reporter, so
  // tests drive fake time and a caught poll failure is always surfaced
  final Duration Function() _now;
  final void Function(Object error, StackTrace stack) _onError;

  Timer? _timer;
  bool _started = false;
  bool _stopped = false;
  bool _pollInFlight = false;
  Duration _earliestForegroundPoll = Duration.zero;

  void start() {
    // Idempotent, a second start must not re-trigger a poll
    if (_started || _stopped) return;
    _started = true;
    _trigger();
  }

  void onForeground() {
    // A foreground before start, after stop, or after a fatal outcome is inert
    // Otherwise it requests a refresh, it does not await the poll
    if (!pollOnForeground || !_started || _stopped || _pollInFlight) return;
    if (_now() >= _earliestForegroundPoll) {
      _timer?.cancel();
      _trigger();
    }
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  void _trigger() {
    if (_stopped || _pollInFlight) return;
    _pollInFlight = true;
    () async {
      try {
        final outcome = await poll();
        _rescheduleAfter(outcome);
      } catch (error, stack) {
        // An unexpected poll failure must not kill polling or become a host-side
        // retry loop, so report it for diagnostics and reschedule at the
        // interval, and a reporter that itself throws must neither wedge polling
        // nor escape uncaught, so contain it and reschedule regardless
        try {
          _onError(error, stack);
        } catch (_) {
          // A broken diagnostic sink cannot be allowed to stop polling
        }
        _rescheduleAfter(null);
      }
    }();
  }

  void _rescheduleAfter(frb.PollOutcome? outcome) {
    _pollInFlight = false;
    if (_stopped) return;
    // A caught exception (null outcome) reschedules at the normal interval
    final delay = outcome == null ? interval : nextPollDelay(outcome, interval);
    if (delay == null) {
      // A fatal provider is terminal, mark stopped so no later timer or
      // foreground event can start another poll
      _stopped = true;
      _timer?.cancel();
      _timer = null;
      return;
    }
    final now = _now();
    _earliestForegroundPoll =
        (outcome != null && _isBackoff(outcome)) ? now + delay : now;
    _timer?.cancel();
    _timer = Timer(delay, _trigger);
  }
}

/// A monotonic elapsed-time source backed by a Stopwatch, the production default
/// when no clock is injected
Duration Function() _monotonicClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}
