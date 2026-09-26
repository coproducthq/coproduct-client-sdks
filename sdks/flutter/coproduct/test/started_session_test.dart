import 'dart:async';

import 'package:coproduct/src/cancellation.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:coproduct/src/session.dart';
import 'package:coproduct/src/started_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _pair = SessionPair(firstSeenAt: 1767225600, sessionCount: 3);

void main() {
  late List<Map<String, frb.FrbContextValue>> late_;
  late List<Object> failures;

  setUp(() {
    late_ = [];
    failures = [];
  });

  StartedSession start(Future<SessionPair> Function() begin) =>
      StartedSession(begin, onFailure: (error, _) => failures.add(error));

  test('a pair that already settled joins the batch even with no budget left',
      () {
    fakeAsync((async) {
      final session = start(() async => _pair);
      async.flushMicrotasks();
      Map<String, frb.FrbContextValue>? batch;
      session
          .forBatch(
            deadline: Duration.zero,
            clock: () => const Duration(seconds: 5),
            cancel: CancellationSignal(),
            onLate: late_.add,
          )
          .then((value) => batch = value);
      async.flushMicrotasks();
      expect(batch, _pair.attributes);
      expect(late_, isEmpty);
    });
  });

  test('a pair arriving within the remainder joins the batch', () {
    fakeAsync((async) {
      final gate = Completer<SessionPair>();
      final session = start(() => gate.future);
      Map<String, frb.FrbContextValue>? batch;
      session
          .forBatch(
            deadline: const Duration(seconds: 1),
            clock: () => async.elapsed,
            cancel: CancellationSignal(),
            onLate: late_.add,
          )
          .then((value) => batch = value);
      async.elapse(const Duration(milliseconds: 400));
      expect(batch, isNull, reason: 'still inside the remainder');
      gate.complete(_pair);
      async.flushMicrotasks();
      expect(batch, _pair.attributes);
      // Checked before time moves on, or a leftover timer would simply fire
      expect(async.pendingTimers, isEmpty,
          reason: 'the deadline timer is cancelled once the pair decides');
      async.elapse(const Duration(seconds: 2));
      expect(late_, isEmpty, reason: 'the batch took it, so the late path must not');
    });
  });

  test('a pair missing the remainder publishes late, once, as one upsert', () {
    fakeAsync((async) {
      final gate = Completer<SessionPair>();
      final session = start(() => gate.future);
      Map<String, frb.FrbContextValue>? batch;
      session
          .forBatch(
            deadline: const Duration(seconds: 1),
            clock: () => async.elapsed,
            cancel: CancellationSignal(),
            onLate: late_.add,
          )
          .then((value) => batch = value);
      async.elapse(const Duration(seconds: 1));
      expect(batch, isEmpty, reason: 'initialize stops waiting at the deadline');
      gate.complete(_pair);
      async.flushMicrotasks();
      expect(late_, [_pair.attributes]);
    });
  });

  test('a spent budget seals before a pending pair can land in the batch', () {
    fakeAsync((async) {
      final gate = Completer<SessionPair>();
      final session = start(() => gate.future);
      Map<String, frb.FrbContextValue>? batch;
      session
          .forBatch(
            deadline: const Duration(seconds: 1),
            clock: () => const Duration(seconds: 1),
            cancel: CancellationSignal(),
            onLate: late_.add,
          )
          .then((value) => batch = value);
      gate.complete(_pair);
      async.flushMicrotasks();
      expect(batch, isEmpty);
      expect(late_, [_pair.attributes], reason: 'exactly one path, never both');
    });
  });

  test('a begin that throws synchronously is reported, not thrown', () {
    // The session starts inside handle construction, where a throw would fail
    // initialize with the handle already open
    fakeAsync((async) {
      late StartedSession session;
      expect(
          () => session = start(() => throw StateError('sync')), returnsNormally);
      async.flushMicrotasks();
      expect(failures, hasLength(1));
      Map<String, frb.FrbContextValue>? batch;
      session
          .forBatch(
            deadline: const Duration(seconds: 1),
            clock: () => async.elapsed,
            cancel: CancellationSignal(),
            onLate: late_.add,
          )
          .then((value) => batch = value);
      async.flushMicrotasks();
      expect(batch, isEmpty);
    });
  });

  test('a cancelled build gets no batch even when the pair already settled', () {
    fakeAsync((async) {
      final session = start(() async => _pair);
      async.flushMicrotasks();
      final cancel = CancellationSignal()..cancel();
      Object? thrown;
      session
          .forBatch(
            deadline: const Duration(seconds: 1),
            clock: () => async.elapsed,
            cancel: cancel,
            onLate: late_.add,
          )
          .catchError((Object error) {
        thrown = error;
        return const <String, frb.FrbContextValue>{};
      });
      async.flushMicrotasks();
      expect(thrown, isA<CoproductInitializationCancelled>());
    });
  });

  test('forBatch is called at most once', () async {
    // A second call could hand the pair to both paths
    final session = StartedSession(() async => _pair, onFailure: (_, _) {});
    Future<Map<String, frb.FrbContextValue>> call() => session.forBatch(
          deadline: const Duration(seconds: 1),
          clock: () => Duration.zero,
          cancel: CancellationSignal(),
          onLate: (_) {},
        );
    await call();
    await expectLater(call(), throwsA(isA<AssertionError>()));
  });

  test('a failure is reported once, publishes nothing, and needs no waiter', () {
    fakeAsync((async) {
      start(() async => throw const SessionAttributesUnavailable(
          SessionAttributesUnavailableCause.storageFailure));
      async.flushMicrotasks();
      expect(failures, [const SessionAttributesUnavailable(
          SessionAttributesUnavailableCause.storageFailure)]);
      expect(late_, isEmpty);
    });
  });

  test('a failure inside the remainder leaves the batch without the pair', () {
    fakeAsync((async) {
      final session =
          start(() async => throw const SessionAttributesUnavailable(
          SessionAttributesUnavailableCause.storageFailure));
      Map<String, frb.FrbContextValue>? batch;
      session
          .forBatch(
            deadline: const Duration(seconds: 1),
            clock: () => async.elapsed,
            cancel: CancellationSignal(),
            onLate: late_.add,
          )
          .then((value) => batch = value);
      async.flushMicrotasks();
      expect(batch, isEmpty);
      expect(failures, hasLength(1));
    });
  });

  test('cancellation ends the wait and a pair arriving afterwards goes nowhere',
      () {
    fakeAsync((async) {
      final gate = Completer<SessionPair>();
      final cancel = CancellationSignal();
      final session = start(() => gate.future);
      Object? thrown;
      session
          .forBatch(
            deadline: const Duration(seconds: 10),
            clock: () => async.elapsed,
            cancel: cancel,
            onLate: late_.add,
          )
          .catchError((Object error) {
        thrown = error;
        return const <String, frb.FrbContextValue>{};
      });
      async.elapse(const Duration(milliseconds: 100));
      cancel.cancel();
      async.flushMicrotasks();
      expect(thrown, isA<CoproductInitializationCancelled>());
      gate.complete(_pair);
      async.flushMicrotasks();
      expect(late_, isEmpty);
    });
  });

  test('a cancellation after the pair won the batch changes nothing', () {
    // The pair and the deadline are not the only contenders: a shutdown can
    // still fire the cancellation after the pair decided the batch
    final errors = <Object>[];
    runZonedGuarded(() {
      fakeAsync((async) {
        final gate = Completer<SessionPair>();
        final cancel = CancellationSignal();
        final session = start(() => gate.future);
        Map<String, frb.FrbContextValue>? batch;
        session
            .forBatch(
              deadline: const Duration(seconds: 10),
              clock: () => async.elapsed,
              cancel: cancel,
              onLate: late_.add,
            )
            .then((value) => batch = value, onError: (_) {});
        async.elapse(const Duration(milliseconds: 100));
        gate.complete(_pair);
        async.flushMicrotasks();
        expect(batch, _pair.attributes);
        cancel.cancel();
        async.elapse(const Duration(seconds: 20));
      });
    }, (error, _) => errors.add(error));
    expect(errors, isEmpty);
    expect(late_, isEmpty);
  });

  test('a reporter or late sink that throws does not escape', () {
    final errors = <Object>[];
    runZonedGuarded(() {
      fakeAsync((async) {
        StartedSession(() async => throw StateError('store'),
            onFailure: (_, _) => throw StateError('reporter'));
        final gate = Completer<SessionPair>();
        StartedSession(() => gate.future, onFailure: (_, _) {}).forBatch(
          deadline: Duration.zero,
          clock: () => Duration.zero,
          cancel: CancellationSignal(),
          onLate: (_) => throw StateError('sink'),
        );
        gate.complete(_pair);
        async.flushMicrotasks();
      });
    }, (error, _) => errors.add(error));
    expect(errors, isEmpty);
  });
}
