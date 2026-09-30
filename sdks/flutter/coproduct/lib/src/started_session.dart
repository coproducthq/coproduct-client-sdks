import 'dart:async';

import 'cancellation.dart';
import 'errors.dart';
import 'rust/api.dart' as frb;
import 'session.dart';

/// A session transaction started once a current core handle exists. Observed
/// from creation, so a failure is reported even if nothing ever waits for it,
/// and remembered once settled, so a pair that arrived early joins the initial
/// batch however late that batch is assembled
class StartedSession {
  StartedSession(
    Future<SessionPair> Function() begin, {
    required void Function(Object error, StackTrace stack) onFailure,
  }) {
    _settled = Future<SessionPair>.sync(begin).then<SessionPair?>(
      (pair) {
        _pair = pair;
        _isSettled = true;
        return pair;
      },
      onError: (Object error, StackTrace stack) {
        _isSettled = true;
        try {
          onFailure(error, stack);
        } catch (_) {
          // Initialization must survive its own diagnostics
        }
        return null;
      },
    );
  }

  late final Future<SessionPair?> _settled;
  SessionPair? _pair;
  bool _isSettled = false;
  bool _forBatchCalled = false;

  /// The pair's attributes for the initial batch, waiting at most until
  /// [deadline] on [clock]. Empty when the pair failed or has not arrived, and
  /// a pair arriving afterwards is handed to [onLate] exactly once, as one
  /// upsert. Throws [CoproductInitializationCancelled] if [cancel] fires, and a
  /// pair arriving after that goes nowhere: it was counted, but it is not
  /// published into a runtime that no longer exists. Call it at most once per
  /// session, since a second call could hand the pair to both paths
  Future<Map<String, frb.FrbContextValue>> forBatch({
    required Duration deadline,
    required Duration Function() clock,
    required CancellationSignal cancel,
    required void Function(Map<String, frb.FrbContextValue> attributes) onLate,
  }) async {
    assert(!_forBatchCalled, 'forBatch is called at most once per session');
    _forBatchCalled = true;
    // Cancellation outranks even a pair that already settled, matching the
    // collector, so a cancelled build never assembles a batch
    if (cancel.isCancelled) {
      throw const CoproductInitializationCancelled();
    }
    if (_isSettled) return _pair?.attributes ?? const {};

    // The same arbitration as the collector's seal: whichever of the pair, the
    // deadline, and cancellation comes first decides, and the loser cannot
    // also publish
    var sealed = false;
    final decided = Completer<Map<String, frb.FrbContextValue>>();
    void seal() {
      if (sealed) return;
      sealed = true;
      decided.complete(const {});
    }

    unawaited(
      _settled.then((pair) {
        if (!sealed) {
          sealed = true;
          decided.complete(pair?.attributes ?? const {});
          return;
        }
        if (pair == null || cancel.isCancelled) return;
        try {
          onLate(pair.attributes);
        } catch (_) {
          // A sink failure must never surface as an unhandled error
        }
      }),
    );

    final remaining = deadline - clock();
    if (remaining <= Duration.zero) {
      // Sealed synchronously rather than by a zero-duration timer: microtasks
      // drain before timers, so a pair settling now would otherwise land in a
      // batch the budget has already closed
      seal();
    } else {
      final timer = Timer(remaining, seal);
      unawaited(decided.future.whenComplete(timer.cancel));
      unawaited(cancel.whenCancelled.then((_) => seal()));
    }

    final attributes = await decided.future;
    if (cancel.isCancelled) {
      throw const CoproductInitializationCancelled();
    }
    return attributes;
  }
}
