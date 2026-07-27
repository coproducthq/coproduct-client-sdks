import 'dart:async';

import 'cancellation.dart';
import 'errors.dart';

/// Serializes the process-wide initialize and shutdown behind a monotonic
/// generation. A concurrent or repeated initialize on a matching identity joins
/// the retained completed client or the in-flight claim, a mismatch is rejected,
/// a shutdown cancels an in-flight init and tears down the current client, and a
/// fresh initialize waits out an in-progress shutdown. Only a build whose
/// generation is still current becomes the current client, so a late completion
/// cannot resurrect a superseded runtime. Cancellation is cooperative, so
/// shutdown waits for the current acquisition boundary to unwind
class CoproductManager<C extends Object> {
  CoproductManager({
    required Future<void> Function(C) shutdownClient,
    required void Function(Object error, StackTrace stack) onCleanupError,
  })  : _shutdownClient = shutdownClient, // ignore: prefer_initializing_formals
        _onCleanupError = onCleanupError; // ignore: prefer_initializing_formals

  final Future<void> Function(C) _shutdownClient;
  final void Function(Object error, StackTrace stack) _onCleanupError;

  int _generation = 0;
  C? _current;
  Object? _currentIdentity;
  Future<C>? _claim;
  Object? _claimIdentity;
  CancellationSignal? _cancel;
  Future<void>? _shutdown;

  /// The current generation, advanced by each initialize and each teardown
  int get generation => _generation;

  Future<C> initialize(
    Object identity,
    Future<C> Function(
            int generation, CancellationSignal cancel, bool Function() isCurrent)
        build,
  ) async {
    // Wait out an in-progress shutdown, ignoring its outcome, re-checking in case
    // another shutdown starts while we wait
    while (true) {
      final shuttingDown = _shutdown;
      if (shuttingDown == null) {
        break;
      }
      await shuttingDown.then((_) {}, onError: (_) {});
    }
    final current = _current;
    if (current != null) {
      if (_currentIdentity == identity) {
        return current;
      }
      throw const CoproductAlreadyInitialized();
    }
    final claimed = _claim;
    if (claimed != null) {
      if (_claimIdentity == identity) {
        return claimed;
      }
      throw const CoproductAlreadyInitialized();
    }

    final generation = ++_generation;
    final cancel = CancellationSignal();
    _cancel = cancel;
    _claimIdentity = identity;
    late final Future<C> claim;
    claim = () async {
      final C client;
      try {
        client = await Future<C>.sync(
            () => build(generation, cancel, () => generation == _generation));
      } catch (error, stack) {
        _releaseClaim(claim, cancel);
        if (generation != _generation) {
          // A shutdown superseded this build while it was failing, so the
          // caller's init was cancelled regardless of the build's own error
          throw const CoproductInitializationCancelled();
        }
        Error.throwWithStackTrace(error, stack);
      }
      if (generation != _generation) {
        // Superseded after producing a client, tear the orphan down without
        // letting a teardown failure shadow the cancellation
        _releaseClaim(claim, cancel);
        try {
          await _shutdownClient(client);
        } catch (error, stack) {
          // A teardown failure must not shadow the cancellation, but it is
          // reported rather than silently discarded, and a reporter that
          // itself throws must not shadow the cancellation either
          try {
            _onCleanupError(error, stack);
          } catch (_) {}
        }
        throw const CoproductInitializationCancelled();
      }
      // Success, promote to the current client and clear the claim, so a later
      // matching initialize joins the completed client and a mismatch is rejected
      _current = client;
      _currentIdentity = identity;
      _releaseClaim(claim, cancel);
      return client;
    }();
    _claim = claim;
    return claim;
  }

  void _releaseClaim(Future<C> claim, CancellationSignal cancel) {
    if (identical(_claim, claim)) {
      _claim = null;
      _claimIdentity = null;
    }
    if (identical(_cancel, cancel)) {
      _cancel = null;
    }
  }

  /// Tears down the current client or cancels an in-flight init, bumping the
  /// generation so any deferred completion is fenced. Concurrent-idempotent, a
  /// true no-op when nothing is live
  Future<void> shutdown() {
    final existing = _shutdown;
    if (existing != null) {
      return existing;
    }
    if (_current == null && _claim == null) {
      // Nothing is live, a true no-op that does not bump the generation
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _shutdown = completer.future;
    unawaited(_runShutdown().then<void>(
      (_) => completer.complete(),
      onError: (Object error, StackTrace stack) =>
          completer.completeError(error, stack),
    ).whenComplete(() {
      if (identical(_shutdown, completer.future)) {
        _shutdown = null;
      }
    }));
    return completer.future;
  }

  Future<void> _runShutdown() async {
    _generation++;
    final cancel = _cancel;
    _cancel = null;
    final current = _current;
    _current = null;
    _currentIdentity = null;
    final claim = _claim;
    _claim = null;
    _claimIdentity = null;
    cancel?.cancel();
    if (current != null) {
      await _shutdownClient(current);
    } else if (claim != null) {
      // Wait for the cancelled in-flight init to unwind so teardown is complete,
      // bounded by the build's least interruptible stage
      await claim.then((_) {}, onError: (_) {});
    }
  }
}
