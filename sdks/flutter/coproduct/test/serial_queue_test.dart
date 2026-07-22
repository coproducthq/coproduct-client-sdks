import 'dart:async';

import 'package:coproduct/src/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('operations run in invocation order and op2 waits for op1 to settle',
      () async {
    final queue = SerialQueue();
    final log = <String>[];
    final firstGate = Completer<void>();

    final first = queue.add<void>(() async {
      log.add('1-start');
      await firstGate.future;
      log.add('1-end');
    });
    final second = queue.add<void>(() async {
      log.add('2-start');
    });

    // Second must not have started while the first is still pending
    await Future<void>.delayed(Duration.zero);
    expect(log, ['1-start']);

    firstGate.complete();
    await Future.wait([first, second]);
    expect(log, ['1-start', '1-end', '2-start']);
  });

  test('a failed operation retains its error on the caller future', () async {
    final queue = SerialQueue();
    await expectLater(
        queue.add<void>(() async => throw StateError('boom')),
        throwsA(isA<StateError>()));
  });

  test('the caller future preserves the original error and its stack', () async {
    final queue = SerialQueue();
    final original = StateError('boom');
    final originalStack = StackTrace.current;
    Object? caughtError;
    StackTrace? caughtStack;
    try {
      await queue.add<void>(() => Future<void>.error(original, originalStack));
    } catch (error, stack) {
      caughtError = error;
      caughtStack = stack;
    }
    expect(identical(caughtError, original), isTrue);
    expect(caughtStack.toString(), originalStack.toString());
  });

  test('a failed operation does not poison the queue', () async {
    final queue = SerialQueue();
    final rejected = queue.add<void>(() async => throw StateError('boom'));
    final valid = queue.add<int>(() async => 7);

    await expectLater(rejected, throwsA(isA<StateError>()));
    expect(await valid, 7);
  });

  test('an ignored failing operation surfaces as an unhandled zone error',
      () async {
    Object? captured;
    await runZonedGuarded(() async {
      final queue = SerialQueue();
      // Intentionally ignore the returned future
      queue.add<void>(() async => throw StateError('boom'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, (error, stack) {
      captured = error;
    });
    expect(captured, isA<StateError>());
  });

  test('separate queues do not block one another', () async {
    final a = SerialQueue();
    final b = SerialQueue();
    final aGate = Completer<void>();

    final aOp = a.add<void>(() => aGate.future);
    final bOp = b.add<int>(() async => 5);

    // b completes even though a is still blocked
    expect(await bOp, 5);
    aGate.complete();
    await aOp;
  });
}
