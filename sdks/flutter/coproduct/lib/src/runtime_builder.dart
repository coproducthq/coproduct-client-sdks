import 'errors.dart';

/// Stages the runtime build so any failure, supersession, or cancellation tears
/// down exactly what was acquired, preserving the original error and stack.
/// Before the runtime exists a rollback closes the handle and the transport,
/// once it exists the runtime owns both and a rollback shuts the runtime down.
/// Every cleanup is guarded so a cleanup failure never shadows the original
/// error, and each cleanup failure is reported through [onCleanupError].
/// [isCurrent] returns false once a newer generation has superseded this build
Future<R> buildRuntime<H extends Object, R extends Object>({
  required Future<H> Function() initHandle,
  required Future<void> Function() disposeTransport,
  required Future<void> Function(H handle) shutdownHandle,
  required Future<void> Function(H handle) publishAttributes,
  required R Function(H handle) createRuntime,
  required void Function(R runtime) startRuntime,
  required Future<void> Function(R runtime) shutdownRuntime,
  required Future<void> Function(H handle) awaitReady,
  required bool Function() isCurrent,
  required void Function(Object error, StackTrace stack) onCleanupError,
}) async {
  final H handle;
  try {
    handle = await initHandle();
  } catch (_) {
    // No handle was created, so only the transport that construction opened
    // needs closing
    await _guard(disposeTransport, onCleanupError);
    rethrow;
  }

  // Tracked separately from the non-nullable success-path local below because
  // a bare type parameter cannot be promoted from R? to R by assignment alone,
  // only by a null check, which the catch block below relies on
  R? builtRuntime;
  try {
    _checkCurrent(isCurrent);
    await publishAttributes(handle);
    _checkCurrent(isCurrent);
    final runtime = createRuntime(handle);
    builtRuntime = runtime;
    startRuntime(runtime);
    await awaitReady(handle);
    _checkCurrent(isCurrent);
    return runtime;
  } catch (error, stack) {
    final built = builtRuntime;
    if (built != null) {
      await _guard(() => shutdownRuntime(built), onCleanupError);
    } else {
      // Attempt both cleanups, so a handle-shutdown failure does not skip the
      // transport dispose
      await _guard(() => shutdownHandle(handle), onCleanupError);
      await _guard(disposeTransport, onCleanupError);
    }
    Error.throwWithStackTrace(error, stack);
  }
}

Future<void> _guard(Future<void> Function() cleanup,
    void Function(Object, StackTrace) onCleanupError) async {
  try {
    await cleanup();
  } catch (error, stack) {
    try {
      // A cleanup failure is reported but never shadows the original error, and
      // a reporter that itself throws must not shadow it either
      onCleanupError(error, stack);
    } catch (_) {}
  }
}

void _checkCurrent(bool Function() isCurrent) {
  if (!isCurrent()) {
    throw const CoproductInitializationCancelled();
  }
}
