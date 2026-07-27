import 'dart:async';

/// A one-shot cancellation signal. [isCancelled] is a synchronous flag, so a
/// caller can poll it before a blocking read, and [whenCancelled] is a future a
/// caller can race in a wait. Owned and completed by the lifecycle manager
class CancellationSignal {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
