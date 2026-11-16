import 'dart:async';

/// Sends one sign-in to Coproduct: the install's anonymous id as `appUserId`
/// and the app's user id as `targetingKey`
typedef IdentifySend =
    Future<void> Function({
      required String appUserId,
      required String targetingKey,
    });

/// Pairs already sent in this process, so a repeated `identify` for the same
/// user does not post again. Shared by every [IdentifySync], because a
/// shutdown and a new initialize build a new one
final Set<(String, String, String)> _processSentPairs = {};

/// Tells Coproduct that this install's anonymous id now belongs to a signed-in
/// user, so purchases made before sign-in follow the user.
///
/// Best-effort and detached from the caller: [link] returns at once and never
/// throws, and a failed send is reported through `onError`
class IdentifySync {
  IdentifySync({
    required String scope,
    required IdentifySend send,
    required void Function(Object error, StackTrace stack) onError,
    Set<(String, String, String)>? sentPairs,
  }) : _scope = scope, // ignore: prefer_initializing_formals
       _send = send, // ignore: prefer_initializing_formals
       _onError = onError, // ignore: prefer_initializing_formals
       _sentPairs = sentPairs ?? _processSentPairs;

  // Separates pairs sent for one SDK key and API from those of another, since
  // the sent set outlives a shutdown
  final String _scope;
  final IdentifySend _send;
  final void Function(Object error, StackTrace stack) _onError;
  final Set<(String, String, String)> _sentPairs;

  /// Starts the send for [anonymousId] and [userId] without waiting for it.
  ///
  /// Does nothing when the anonymous id is unknown, when the two ids are
  /// equal, or when this pair was already sent in this process. A pair whose
  /// send failed is forgotten, so the next `identify` tries it again
  void link({required String? anonymousId, required String userId}) {
    if (anonymousId == null || anonymousId.isEmpty || anonymousId == userId) {
      return;
    }
    final pair = (_scope, anonymousId, userId);
    if (!_sentPairs.add(pair)) return;
    unawaited(_run(pair, anonymousId, userId));
  }

  Future<void> _run(
    (String, String, String) pair,
    String anonymousId,
    String userId,
  ) async {
    try {
      await _send(appUserId: anonymousId, targetingKey: userId);
    } catch (error, stack) {
      _sentPairs.remove(pair);
      try {
        _onError(error, stack);
      } catch (_) {
        // A reporter that throws must not become an unhandled async error
      }
    }
  }
}
