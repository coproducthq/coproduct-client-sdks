import 'dart:async';

/// Runs operations one at a time in the order they were added. Each add returns
/// a caller-facing future that completes with the operation's own value or error,
/// while a separate internal tail always completes successfully so a failed
/// operation never blocks the next one. The two futures are kept distinct on
/// purpose: attaching an error listener to the caller future would defuse the
/// unhandled-error behavior a caller expects when it ignores a failing future
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> add<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
