import 'dart:async';

import 'package:coproduct/src/auto_upsert.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:coproduct/src/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = frb.FrbContextValue.string('phone');

void main() {
  test('publishes through the shared queue, after work already queued', () async {
    final order = <String>[];
    final queue = SerialQueue();
    final upsert = AutoUpsert(
      queue: queue,
      isCurrent: () => true,
      send: (attributes) async => order.add('upsert'),
      onError: (_, _) {},
    );

    // Gated rather than timed: a delay plus a pump is a race, and a test that
    // sometimes passes for the wrong reason is worse than no test
    final release = Completer<void>();
    final identity = queue.add(() async {
      await release.future;
      order.add('identify');
    });
    upsert.publish({'device_type': _phone});

    release.complete();
    await identity;
    await queue.add(() async {}); // drains behind the upsert

    expect(order, ['identify', 'upsert']);
  });

  test('drops the write when the generation is superseded while it waits',
      () async {
    var sent = 0;
    var current = true;
    final queue = SerialQueue();
    final upsert = AutoUpsert(
      queue: queue,
      isCurrent: () => current,
      send: (attributes) async => sent++,
      onError: (_, _) {},
    );

    // Supersede from inside a queued operation, so the upsert is already
    // waiting behind it rather than being checked before it was enqueued
    final supersede = queue.add(() async => current = false);
    upsert.publish({'device_type': _phone});
    await supersede;
    await queue.add(() async {});

    expect(sent, 0,
        reason: 'the check must run when the write executes, not when it is queued');
  });

  test('a send failure is reported and does not break the queue', () async {
    final errors = <Object>[];
    final queue = SerialQueue();
    final upsert = AutoUpsert(
      queue: queue,
      isCurrent: () => true,
      send: (attributes) async => throw StateError('boom'),
      onError: (error, _) => errors.add(error),
    );

    upsert.publish({'device_type': _phone});
    await queue.add(() async {});
    expect(errors, hasLength(1));

    var later = false;
    await queue.add(() async => later = true);
    expect(later, isTrue);
  });

  test('a caller map mutated after publish does not change what is sent', () async {
    Map<String, frb.FrbContextValue>? sent;
    final queue = SerialQueue();
    final release = Completer<void>();
    final blocker = queue.add(() => release.future);
    final upsert = AutoUpsert(
      queue: queue,
      isCurrent: () => true,
      send: (attributes) async => sent = attributes,
      onError: (_, _) {},
    );

    final attributes = <String, frb.FrbContextValue>{'device_type': _phone};
    upsert.publish(attributes);
    attributes['device_type'] = const frb.FrbContextValue.string('tablet');
    attributes['network_type'] = const frb.FrbContextValue.string('wifi');

    release.complete();
    await blocker;
    await queue.add(() async {});

    expect(sent, {'device_type': _phone});
  });

  test('a throwing error reporter does not escape', () async {
    final queue = SerialQueue();
    AutoUpsert(
      queue: queue,
      isCurrent: () => true,
      send: (attributes) async => throw StateError('boom'),
      onError: (_, _) => throw StateError('reporter exploded'),
    ).publish({'device_type': _phone});

    await queue.add(() async {});
    await pumpEventQueue();
  });

  test('an empty attribute map enqueues nothing', () async {
    var sent = 0;
    final queue = SerialQueue();
    AutoUpsert(
      queue: queue,
      isCurrent: () => true,
      send: (attributes) async => sent++,
      onError: (_, _) {},
    ).publish({});

    await queue.add(() async {});
    expect(sent, 0);
  });
}
