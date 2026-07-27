import 'dart:async';

import 'http_transport.dart';
import 'scheduler.dart';

/// Owns the polling scheduler, the HTTP transport, and the foreground listener
/// for one runtime generation, and tears them down in order. The core shutdown
/// latch is set before the transport client is closed, so the transport is never
/// closed while the core might still poll through it, and the transport is closed
/// even if the core shutdown call throws
class CoproductRuntime {
  CoproductRuntime({
    required this.generation,
    required this.scheduler,
    required this.transport,
    required Future<void> Function() coreShutdown,
    void Function()? disposeForeground,
  })  :
        // ignore: prefer_initializing_formals
        _coreShutdown = coreShutdown,
        // ignore: prefer_initializing_formals
        _disposeForeground = disposeForeground;

  final int generation;
  final Scheduler scheduler;
  final HttpTransport transport;
  final Future<void> Function() _coreShutdown;
  final void Function()? _disposeForeground;
  Future<void>? _shutdown;

  /// True once shutdown has begun, not necessarily completed
  bool get isShutDown => _shutdown != null;

  /// Starts polling with an immediate first tick
  void start() {
    scheduler.start();
  }

  /// Ordered, reentrancy-safe, concurrent-idempotent teardown. The shared future
  /// is installed before teardown begins, so a second or reentrant call joins it
  Future<void> shutdown() {
    final existing = _shutdown;
    if (existing != null) {
      return existing;
    }
    final completer = Completer<void>();
    _shutdown = completer.future;
    unawaited(_runShutdown().then<void>(
      (_) => completer.complete(),
      onError: (Object error, StackTrace stack) =>
          completer.completeError(error, stack),
    ));
    return completer.future;
  }

  Future<void> _runShutdown() async {
    try {
      // A foreground disposal failure must not skip stopping the scheduler,
      // setting the core latch, or closing the transport
      _disposeForeground?.call();
    } finally {
      scheduler.stop();
      try {
        await _coreShutdown();
      } finally {
        // Close the transport even if the core latch call failed, so a failing
        // shutdown never leaks the client
        await transport.dispose();
      }
    }
  }
}
