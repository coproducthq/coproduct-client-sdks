import 'dart:async';

import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:coproduct/src/scheduler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextPollDelay', () {
    const interval = Duration(seconds: 60);
    test('normal-cadence outcomes return the interval', () {
      for (final o in [
        const frb.PollOutcome.updated(),
        const frb.PollOutcome.notModified(),
        const frb.PollOutcome.retrying(),
        const frb.PollOutcome.dedupedSkipped(),
      ]) {
        expect(nextPollDelay(o, interval), interval);
      }
    });
    test('rate limited returns max(retryAfter, interval)', () {
      expect(nextPollDelay(const frb.PollOutcome.rateLimited(retryAfterSecs: 10),
          interval), interval);
      expect(
          nextPollDelay(
              const frb.PollOutcome.rateLimited(retryAfterSecs: 120), interval),
          const Duration(seconds: 120));
    });
    test('stale backs off, fatal stops', () {
      expect(nextPollDelay(const frb.PollOutcome.stale(), interval),
          const Duration(seconds: 300));
      expect(nextPollDelay(const frb.PollOutcome.fatal(), interval), isNull);
    });
  });

  group('Scheduler', () {
    test('polls immediately on start and does not overlap', () {
      fakeAsync((async) {
        var inFlight = 0;
        var maxInFlight = 0;
        var polls = 0;
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (_, _) {},
          poll: () async {
            polls++;
            inFlight++;
            maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
            await Future<void>.delayed(const Duration(seconds: 1));
            inFlight--;
            return const frb.PollOutcome.updated();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        expect(polls, 1); // immediate first poll, still in flight
        async.elapse(const Duration(seconds: 1)); // first poll completes
        async.elapse(const Duration(seconds: 60)); // the interval timer fires
        scheduler.stop();
        expect(maxInFlight, 1); // never overlapped
        expect(polls, greaterThan(1)); // rescheduled
      });
    });

    test('stops permanently on fatal', () {
      fakeAsync((async) {
        var polls = 0;
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (_, _) {},
          poll: () async {
            polls++;
            return const frb.PollOutcome.fatal();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        expect(polls, 1);
        async.elapse(const Duration(minutes: 10));
        scheduler.stop();
        expect(polls, 1); // fatal stopped scheduling
      });
    });

    test('an unexpected poll exception is reported and reschedules', () {
      fakeAsync((async) {
        var polls = 0;
        Object? reportedError;
        StackTrace? reportedStack;
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (error, stack) {
            reportedError = error;
            reportedStack = stack;
          },
          poll: () async {
            polls++;
            if (polls == 1) throw StateError('boom');
            return const frb.PollOutcome.updated();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        expect(reportedError, isA<StateError>()); // reported, not swallowed
        expect(reportedStack, isNotNull);
        async.elapse(const Duration(seconds: 60)); // the reschedule timer fires
        scheduler.stop();
        expect(polls, greaterThan(1)); // recovered after the exception
      });
    });

    test('a throwing error reporter does not wedge polling', () {
      fakeAsync((async) {
        var polls = 0;
        var reported = 0;
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (error, stack) {
            reported++;
            throw StateError('reporter boom');
          },
          poll: () async {
            polls++;
            if (polls == 1) throw StateError('poll boom');
            return const frb.PollOutcome.updated();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        expect(polls, 1); // the first poll threw
        expect(reported, 1); // the reporter was invoked and threw
        async.elapse(const Duration(seconds: 60)); // the reschedule still fires
        scheduler.stop();
        expect(polls, greaterThan(1)); // polling recovered despite the reporter
      });
    });

    test('stop during an in-flight poll does not reschedule', () {
      fakeAsync((async) {
        var polls = 0;
        final gate = Completer<void>();
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (_, _) {},
          poll: () async {
            polls++;
            await gate.future;
            return const frb.PollOutcome.updated();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        scheduler.stop();
        gate.complete();
        async.elapse(const Duration(minutes: 5));
        expect(polls, 1); // the in-flight poll settled but did not reschedule
      });
    });

    test('a foreground event refreshes during normal cadence', () {
      fakeAsync((async) {
        var polls = 0;
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (_, _) {},
          poll: () async {
            polls++;
            return const frb.PollOutcome.updated();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        expect(polls, 1); // first poll done, the next timer is 60s away
        async.elapse(const Duration(seconds: 5)); // still inside the interval
        scheduler.onForeground();
        async.flushMicrotasks();
        scheduler.stop();
        expect(polls, 2); // foreground forced an off-schedule refresh
      });
    });

    test('a foreground event does not shorten an active backoff', () {
      fakeAsync((async) {
        var polls = 0;
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (_, _) {},
          poll: () async {
            polls++;
            return const frb.PollOutcome.stale();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        expect(polls, 1); // stale opened a 300s backoff window
        async.elapse(const Duration(seconds: 30)); // still inside the window
        scheduler.onForeground();
        async.flushMicrotasks();
        scheduler.stop();
        expect(polls, 1); // foreground did not re-poll inside the stale backoff
      });
    });

    test('a foreground event after fatal does not poll', () {
      fakeAsync((async) {
        var polls = 0;
        final scheduler = Scheduler(
          interval: const Duration(seconds: 60),
          pollOnForeground: true,
          clock: () => async.elapsed,
          onError: (_, _) {},
          poll: () async {
            polls++;
            return const frb.PollOutcome.fatal();
          },
        );
        scheduler.start();
        async.flushMicrotasks();
        expect(polls, 1); // fatal stopped scheduling
        async.elapse(const Duration(seconds: 5));
        scheduler.onForeground();
        async.flushMicrotasks();
        scheduler.stop();
        expect(polls, 1); // foreground after fatal is inert
      });
    });
  });
}
