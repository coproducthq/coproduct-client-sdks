import 'dart:async';

import 'package:coproduct/src/auto_upsert.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/network_type.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:coproduct/src/serial_queue.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// One listen the service opened: its epoch and the controller a test drives
class _Listen {
  _Listen(this.epoch, this.controller);
  final int epoch;
  final StreamController<Object?> controller;

  void emit(String value, {int? epoch}) =>
      controller.add({'epoch': epoch ?? this.epoch, 'value': value});
}

/// Stands in for the platform event channel. Every call is a new listen, as
/// with the channel's event stream, and the log records listens and cancels in
/// order. A broadcast controller, like the real one: its onCancel runs at once and
/// cancel() never waits on it, so nothing here can model a native
/// acknowledgement the production stream does not expose
class _FakeEvents {
  final List<_Listen> listens = [];
  final List<String> log = [];

  Stream<Object?> call(int epoch) {
    final controller = StreamController<Object?>.broadcast(
      onListen: () => log.add('listen $epoch'),
      onCancel: () => log.add('cancel $epoch'),
    );
    listens.add(_Listen(epoch, controller));
    return controller.stream;
  }

  _Listen get latest => listens.last;
  int get live => listens.where((l) => l.controller.hasListener).length;
}

/// The real AutoUpsert over a recording send, so dedup and the queue's
/// ordering are exercised as they run in production
class _Core {
  // Lazy, not eager: SerialQueue's first Future is created wherever the field
  // is first touched, and every touch in these tests happens inside fakeAsync.
  // Built eagerly here, it would be created in setUp, outside the fake zone,
  // and a real Future chained from a fake one never resumes under
  // flushMicrotasks
  late final SerialQueue queue = SerialQueue();
  final List<String> values = [];
  bool current = true;

  late final AutoUpsert upsert = AutoUpsert(
    queue: queue,
    isCurrent: () => current,
    send: (attributes) async => values.add(
        (attributes['network_type']! as frb.FrbContextValue_String).field0),
    onError: (_, _) {},
  );
}

void main() {
  late _FakeEvents events;
  late _Core core;
  void Function()? resume;
  late int resumeDisposals;
  late int unavailable;
  late List<String?> printed;
  late DebugPrintCallback previousDebugPrint;

  NetworkTypeService service({Future<AutoUpsert?>? upsert}) =>
      NetworkTypeService(
        events: events.call,
        upsert: upsert ?? Future<AutoUpsert?>.value(core.upsert),
        bindResume: (onResume) {
          resume = onResume;
          return () => resumeDisposals++;
        },
        onUnavailable: () => unavailable++,
      );

  setUp(() {
    events = _FakeEvents();
    core = _Core();
    resume = null;
    resumeDisposals = 0;
    unavailable = 0;
    printed = [];
    previousDebugPrint = debugPrint;
    // The service's diagnostics are assert-gated debugPrint calls: captured
    // here so the backoff and malformed-event tests, which trigger many of
    // them, stay quiet, and so one test can assert the diagnostic fired
    debugPrint = (String? message, {int? wrapWidth}) => printed.add(message);
  });

  tearDown(() {
    debugPrint = previousDebugPrint;
  });

  test('the first listen publishes the current value', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      expect(events.listens, hasLength(1));
      events.latest.emit('wifi');
      async.flushMicrotasks();
      expect(core.values, ['wifi']);
    });
  });

  test('parse accepts only the envelope a matching plugin sends', () {
    expect(NetworkTypeEvent.parse({'epoch': 3, 'value': 'none'})?.value, 'none');
    for (final raw in <Object?>[
      'wifi',
      null,
      {'epoch': '3', 'value': 'wifi'},
      {'epoch': 3.0, 'value': 'wifi'},
      {'epoch': 3, 'value': 'bluetooth'},
      {'epoch': 3},
    ]) {
      expect(NetworkTypeEvent.parse(raw), isNull, reason: '$raw');
    }
  });

  test('nothing publishes before the initial batch, and nothing at all if the '
      'build fails', () {
    fakeAsync((async) {
      final batch = Completer<AutoUpsert?>();
      service(upsert: batch.future).start();
      async.flushMicrotasks();
      events.latest.emit('wifi');
      async.flushMicrotasks();
      expect(core.values, isEmpty);
      batch.complete(core.upsert);
      async.flushMicrotasks();
      expect(core.values, ['wifi']);

      events = _FakeEvents();
      final failed = Completer<AutoUpsert?>();
      service(upsert: failed.future).start();
      async.flushMicrotasks();
      events.latest.emit('cellular');
      failed.complete(null);
      async.flushMicrotasks();
      expect(core.values, ['wifi']);
    });
  });

  test('a repeated value within one listen publishes once, even when both are '
      'queued before either runs', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      final gate = Completer<void>();
      unawaited(core.queue.add(() => gate.future));
      events.latest
        ..emit('wifi')
        ..emit('wifi')
        ..emit('cellular')
        ..emit('cellular');
      async.flushMicrotasks();
      gate.complete();
      async.flushMicrotasks();
      expect(core.values, ['wifi', 'cellular']);
    });
  });

  test('a resume cancels the listen before the next epoch listens, and the new '
      "listen's value is published", () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      final first = events.latest;
      first.emit('wifi');
      async.flushMicrotasks();
      resume!();
      async.flushMicrotasks();
      final second = events.latest;
      expect(second.epoch, greaterThan(first.epoch));
      expect(events.log, [
        'listen ${first.epoch}',
        'cancel ${first.epoch}',
        'listen ${second.epoch}',
      ]);
      // Published again rather than suppressed: dedup belongs to one listen,
      // and the core's own no-op check absorbs a repeat without notifying
      second.emit('wifi');
      async.flushMicrotasks();
      expect(core.values, ['wifi', 'wifi']);
    });
  });

  test('an event from a superseded epoch is dropped', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      final old = events.latest.epoch;
      resume!();
      async.flushMicrotasks();
      events.latest.emit('cellular', epoch: old);
      async.flushMicrotasks();
      expect(core.values, isEmpty);
    });
  });

  test('an event queued behind a slow identify when the resubscription starts '
      'is dropped and does not suppress the same value later', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      final identify = Completer<void>();
      unawaited(core.queue.add(() => identify.future));
      events.latest.emit('wifi');
      async.flushMicrotasks();
      resume!();
      async.flushMicrotasks();
      events.latest.emit('wifi');
      async.flushMicrotasks();
      identify.complete();
      async.flushMicrotasks();
      expect(core.values, ['wifi']);
    });
  });

  test('a write queued before a failure never lands once the failure moves '
      'the epoch on', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      final gate = Completer<void>();
      unawaited(core.queue.add(() => gate.future));
      events.latest.emit('wifi');
      async.flushMicrotasks();
      events.latest.controller.addError(StateError('refused'));
      async.flushMicrotasks();
      // Released well before the retry floor elapses, so only the epoch bump
      // in _onFailure, not a resubscription, can be protecting this write
      gate.complete();
      async.flushMicrotasks();
      expect(core.values, isEmpty);
    });
  });

  test('a malformed event is dropped without resubscribing', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      final listen = events.latest;
      listen.controller
        ..add('wifi')
        ..add({'epoch': listen.epoch, 'value': 'bluetooth'})
        ..add({'epoch': 'x', 'value': 'wifi'});
      async.elapse(const Duration(minutes: 5));
      expect(core.values, isEmpty);
      expect(events.listens, hasLength(1));
      expect(printed, contains('coproduct: dropped a malformed network_type event'));
    });
  });

  test('a stream error resubscribes after the floor, and repeated failures '
      'double the delay up to the cap', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      var expected = NetworkTypeService.retryFloor;
      for (var failure = 1; failure <= 9; failure++) {
        events.latest.controller.addError(StateError('refused'));
        async.flushMicrotasks();
        expect(events.live, 0, reason: 'the failed listen is cancelled');
        async.elapse(expected - const Duration(milliseconds: 1));
        expect(events.listens, hasLength(failure), reason: 'retry $failure early');
        async.elapse(const Duration(milliseconds: 1));
        expect(events.listens, hasLength(failure + 1), reason: 'retry $failure');
        final doubled = expected * 2;
        expected = doubled > NetworkTypeService.retryCap
            ? NetworkTypeService.retryCap
            : doubled;
      }
      expect(expected, NetworkTypeService.retryCap);
    });
  });

  test('the delay resets only after a valid event, not a bare resubscribe', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      events.latest.controller.addError(StateError('refused'));
      async.elapse(NetworkTypeService.retryFloor);
      events.latest.controller.addError(StateError('refused'));
      async.elapse(NetworkTypeService.retryFloor);
      expect(events.listens, hasLength(2), reason: 'the second wait doubled');
      async.elapse(NetworkTypeService.retryFloor);
      expect(events.listens, hasLength(3));
      events.latest.emit('wifi');
      async.flushMicrotasks();
      events.latest.controller.addError(StateError('refused'));
      async.elapse(NetworkTypeService.retryFloor);
      expect(events.listens, hasLength(4), reason: 'a valid event reset it');
    });
  });

  test('a stale-epoch event on the current listen does not reset the backoff '
      'delay', () {
    // The channel's event stream shares one message handler per channel name,
    // so a message still in flight from a listen that has already been
    // superseded can arrive on the subscription that replaced it
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      final stale = events.latest.epoch;
      events.latest.controller.addError(StateError('refused'));
      async.elapse(NetworkTypeService.retryFloor);
      // The retry listens, and the next failure's delay is now 2s
      events.latest.emit('wifi', epoch: stale);
      async.flushMicrotasks();
      events.latest.controller.addError(StateError('refused'));
      final before = events.listens.length;
      async.elapse(NetworkTypeService.retryFloor);
      expect(events.listens, hasLength(before),
          reason: 'the stale event must not have reset the delay to the floor');
      async.elapse(NetworkTypeService.retryFloor);
      expect(events.listens, hasLength(before + 1));
    });
  });

  test('a missing network channel reports once and stops observing for good',
      () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      events.latest.controller.addError(const HostContextUnavailable());
      async.flushMicrotasks();
      expect(unavailable, 1);
      expect(events.live, 0, reason: 'the failed listen is cancelled');
      async.elapse(NetworkTypeService.retryCap * 2);
      expect(events.listens, hasLength(1), reason: 'no retry is scheduled');
      for (var i = 0; i < 3; i++) {
        resume!();
        async.flushMicrotasks();
      }
      expect(events.listens, hasLength(1), reason: 'a resume opens no listen');
      expect(unavailable, 1);
    });
  });

  test('an unexpected end of the stream is a failure', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      unawaited(events.latest.controller.close());
      async.flushMicrotasks();
      async.elapse(NetworkTypeService.retryFloor);
      expect(events.listens, hasLength(2));
    });
  });

  test('a resume bypasses a pending retry delay and replaces it', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      events.latest.controller.addError(StateError('refused'));
      async.flushMicrotasks();
      resume!();
      async.flushMicrotasks();
      expect(events.listens, hasLength(2));
      async.elapse(const Duration(minutes: 5));
      expect(events.listens, hasLength(2), reason: 'the old timer did not fire');
    });
  });

  test('rapid rechecks cancel each listen before the next one starts and '
      'leave one listen, on the newest epoch', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      resume!();
      resume!();
      events.latest.controller.addError(StateError('refused'));
      async.elapse(NetworkTypeService.retryFloor);
      resume!();
      async.flushMicrotasks();
      final epochs = events.listens.map((l) => l.epoch).toList();
      expect(epochs, hasLength(5));
      // Every cancel is sent before the listen that replaces it, which is what
      // puts it ahead on the ordered channel
      expect(events.log, [
        for (var i = 0; i < epochs.length; i++) ...[
          'listen ${epochs[i]}',
          if (i < epochs.length - 1) 'cancel ${epochs[i]}',
        ],
      ]);
      expect(events.live, 1);
      expect(events.latest.controller.hasListener, isTrue);
      for (final stale in events.listens.take(4)) {
        events.latest.emit('wifi', epoch: stale.epoch);
      }
      async.flushMicrotasks();
      expect(core.values, isEmpty, reason: 'a stale epoch cannot publish');
      events.latest.emit('cellular');
      async.flushMicrotasks();
      expect(core.values, ['cellular']);
    });
  });

  test('repeated resume and failure cycles leave at most one listen', () {
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      for (var cycle = 0; cycle < 20; cycle++) {
        if (cycle.isEven) {
          resume!();
        } else {
          events.latest.controller.addError(StateError('refused'));
        }
        async.elapse(const Duration(seconds: 2));
        expect(events.live, lessThanOrEqualTo(1), reason: 'cycle $cycle');
      }
    });
  });

  test('failures back off to the cap and keep the last value', () {
    // No way to unpublish an attribute exists, so the last observed transport
    // is retained through a failure rather than cleared or replaced
    fakeAsync((async) {
      service().start();
      async.flushMicrotasks();
      events.latest.emit('wifi');
      async.flushMicrotasks();
      for (var failure = 0; failure < 12; failure++) {
        events.latest.controller.addError(StateError('refused'));
        async.elapse(NetworkTypeService.retryCap);
      }
      expect(core.values, ['wifi']);
    });
  });

  test('close cancels the listen, the pending retry, and the resume binding, '
      'and drops a value already queued', () {
    fakeAsync((async) {
      final network = service()..start();
      async.flushMicrotasks();
      final gate = Completer<void>();
      unawaited(core.queue.add(() => gate.future));
      events.latest.emit('wifi');
      async.flushMicrotasks();
      events.latest.controller.addError(StateError('refused'));
      async.flushMicrotasks();
      network.close();
      gate.complete();
      async.elapse(const Duration(minutes: 5));
      resume!();
      async.flushMicrotasks();
      expect(core.values, isEmpty);
      expect(events.listens, hasLength(1));
      expect(events.live, 0);
      expect(resumeDisposals, 1);
    });
  });

  test('epochs keep increasing across services', () {
    fakeAsync((async) {
      service()
        ..start()
        ..close();
      async.flushMicrotasks();
      final first = events.latest.epoch;
      service().start();
      async.flushMicrotasks();
      expect(events.latest.epoch, greaterThan(first));
    });
  });
}
