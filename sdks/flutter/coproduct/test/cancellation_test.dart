import 'package:coproduct/src/cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts uncancelled, cancel flips the flag and completes the future',
      () async {
    final signal = CancellationSignal();
    expect(signal.isCancelled, isFalse);
    var completed = false;
    signal.whenCancelled.then((_) => completed = true);
    signal.cancel();
    expect(signal.isCancelled, isTrue); // synchronous, before any microtask
    await signal.whenCancelled;
    expect(completed, isTrue);
  });

  test('cancel is idempotent', () async {
    final signal = CancellationSignal();
    signal.cancel();
    signal.cancel(); // must not throw on a completed completer
    expect(signal.isCancelled, isTrue);
    await signal.whenCancelled;
  });
}
