import 'dart:async';
import 'dart:developer' as developer;

import 'package:http/http.dart' show ClientException;

import 'paywall/paywall_client.dart' show PaywallServerError;

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
/// throws.
///
/// A send that fails because the network is down, times out, or the server is
/// busy is tried again after each of [retryDelays], and stays quiet if it
/// never gets through, since being offline is not a bug. The server's
/// `install_limit_reached` answer is expected too and is only logged. Any other
/// failure, such as a rejected key, is reported through `onError`
class IdentifySync {
  IdentifySync({
    required String scope,
    required IdentifySend send,
    required void Function(Object error, StackTrace stack) onError,
    Set<(String, String, String)>? sentPairs,
    List<Duration> retryDelays = defaultRetryDelays,
  }) : _scope = scope, // ignore: prefer_initializing_formals
       _send = send, // ignore: prefer_initializing_formals
       _onError = onError, // ignore: prefer_initializing_formals
       _sentPairs = sentPairs ?? _processSentPairs,
       _retryDelays = retryDelays;

  /// The waits before each retry of a send that failed for a reason that can
  /// pass: two seconds, ten seconds, then a minute
  static const List<Duration> defaultRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 10),
    Duration(seconds: 60),
  ];

  // Separates pairs sent for one SDK key and API from those of another, since
  // the sent set outlives a shutdown
  final String _scope;
  final IdentifySend _send;
  final void Function(Object error, StackTrace stack) _onError;
  final Set<(String, String, String)> _sentPairs;
  final List<Duration> _retryDelays;

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
    var retries = 0;
    while (true) {
      try {
        await _send(appUserId: anonymousId, targetingKey: userId);
        return;
      } catch (error, stack) {
        if (_canPass(error) && retries < _retryDelays.length) {
          await Future<void>.delayed(_retryDelays[retries++]);
          continue;
        }
        // Forgotten, so the next identify tries this pair again
        _sentPairs.remove(pair);
        if (_isExpected(error)) {
          developer.log(
            'Could not link this install to the signed-in user: $error',
            name: 'coproduct',
            level: 900,
          );
          return;
        }
        try {
          _onError(error, stack);
        } catch (_) {
          // A reporter that throws must not become an unhandled async error
        }
        return;
      }
    }
  }

  /// Whether the same send can succeed later: no network, a timeout, no
  /// answer, or a server that is busy or failing
  static bool _canPass(Object error) {
    if (error is TimeoutException || error is ClientException) return true;
    if (error is PaywallServerError) {
      final status = error.statusCode;
      return status == 0 || status == 408 || status == 429 || status >= 500;
    }
    return false;
  }

  /// Failures that are not a bug in the app: the ones above that never got
  /// through, and the project's limit on installs linked to one user
  static bool _isExpected(Object error) =>
      _canPass(error) ||
      (error is PaywallServerError && error.code == 'install_limit_reached');
}
