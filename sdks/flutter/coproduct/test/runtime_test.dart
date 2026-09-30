import 'dart:async';

import 'package:coproduct/src/auto_upsert.dart';
import 'package:coproduct/src/http_transport.dart';
import 'package:coproduct/src/network_type.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:coproduct/src/runtime.dart';
import 'package:coproduct/src/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Records when its client is closed, so the shutdown ordering is observable
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.log);
  final List<String> log;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream<List<int>>.empty(), 200);
  }

  @override
  void close() => log.add('transport-closed');
}

Scheduler _scheduler(void Function() onPoll) => Scheduler(
  interval: const Duration(milliseconds: 20),
  pollOnForeground: true,
  onError: (_, _) {},
  poll: () async {
    onPoll();
    return const frb.PollOutcome.updated();
  },
);

/// A Scheduler that logs its own stop, so a shutdown ordering test can observe
/// when the scheduler actually stopped rather than only inferring it
class _LoggingScheduler extends Scheduler {
  _LoggingScheduler(
    this._log, {
    required super.poll,
    required super.interval,
    required super.pollOnForeground,
    required super.onError,
  });

  final List<String> _log;

  @override
  void stop() {
    _log.add('scheduler-stopped');
    super.stop();
  }
}

Scheduler _loggingScheduler(List<String> log) => _LoggingScheduler(
  log,
  interval: const Duration(milliseconds: 20),
  pollOnForeground: true,
  onError: (_, _) {},
  poll: () async => const frb.PollOutcome.updated(),
);

void main() {
  test(
    'start polls, shutdown tears down in order and stops the scheduler first',
    () async {
      final log = <String>[];
      var polls = 0;
      final firstPoll = Completer<void>();
      late Scheduler scheduler;
      scheduler = _scheduler(() {
        polls++;
        if (!firstPoll.isCompleted) firstPoll.complete();
      });
      final runtime = CoproductRuntime(
        generation: 1,
        scheduler: scheduler,
        transport: HttpTransport(
          client: _RecordingClient(log),
          requestTimeout: const Duration(seconds: 1),
        ),
        coreShutdown: () async {
          // The scheduler is already stopped, so a foreground here starts no poll,
          // and a triggered poll would increment synchronously, so no wait is needed
          final before = polls;
          scheduler.onForeground();
          expect(
            polls,
            before,
            reason: 'scheduler must be stopped before core',
          );
          log.add('core-shutdown');
        },
        disposeForeground: () => log.add('foreground-disposed'),
      );

      runtime.start();
      // start() triggers the first poll synchronously, so a regression that made
      // it asynchronous fails here at once rather than hanging on a future
      expect(firstPoll.isCompleted, isTrue);
      expect(polls, greaterThan(0));

      await runtime.shutdown();
      expect(log, ['foreground-disposed', 'core-shutdown', 'transport-closed']);
      expect(runtime.isShutDown, isTrue);
    },
  );

  test(
    'a concurrent or reentrant second shutdown joins the first teardown',
    () async {
      final log = <String>[];
      final gate = Completer<void>();
      late CoproductRuntime runtime;
      var reentrantResult = -1;
      runtime = CoproductRuntime(
        generation: 1,
        scheduler: _scheduler(() {}),
        transport: HttpTransport(
          client: _RecordingClient(log),
          requestTimeout: const Duration(seconds: 1),
        ),
        coreShutdown: () async {
          await gate.future;
          log.add('core-shutdown');
        },
        // A reentrant shutdown from within foreground disposal must join, not
        // start a second teardown
        disposeForeground: () {
          reentrantResult = identical(runtime.shutdown(), runtime.shutdown())
              ? 1
              : 0;
        },
      );
      runtime.start();
      final first = runtime.shutdown();
      final second = runtime.shutdown();
      gate.complete();
      await Future.wait([first, second]);
      expect(log.where((e) => e == 'core-shutdown').length, 1); // ran once
      expect(reentrantResult, 1); // the reentrant calls joined the same future
    },
  );

  test('the transport is closed even if the core shutdown throws', () async {
    final log = <String>[];
    final runtime = CoproductRuntime(
      generation: 1,
      scheduler: _scheduler(() {}),
      transport: HttpTransport(
        client: _RecordingClient(log),
        requestTimeout: const Duration(seconds: 1),
      ),
      coreShutdown: () async => throw StateError('latch failed'),
    );
    runtime.start();
    await expectLater(runtime.shutdown(), throwsA(isA<StateError>()));
    expect(log, contains('transport-closed'));
  });

  test(
    'a foreground disposal failure does not skip the later stages',
    () async {
      final log = <String>[];
      final runtime = CoproductRuntime(
        generation: 1,
        scheduler: _scheduler(() {}),
        transport: HttpTransport(
          client: _RecordingClient(log),
          requestTimeout: const Duration(seconds: 1),
        ),
        coreShutdown: () async => log.add('core-shutdown'),
        disposeForeground: () => throw StateError('foreground'),
      );
      runtime.start();
      await expectLater(runtime.shutdown(), throwsA(isA<StateError>()));
      // The core latch was still set and the transport still closed
      expect(log, ['core-shutdown', 'transport-closed']);
    },
  );

  group('network observation', () {
    NetworkTypeService network(List<String> log) => NetworkTypeService(
      events: (epoch) {
        log.add('network-listen');
        return StreamController<Object?>.broadcast(
          onCancel: () => log.add('network-cancelled'),
        ).stream;
      },
      upsert: Future<AutoUpsert?>.value(),
      bindResume: (_) => null,
      onUnavailable: () {},
    );

    test(
      'starts with the runtime and closes at shutdown, after the foreground '
      'listener and before the core, and stops the scheduler in between',
      () async {
        final log = <String>[];
        final runtime = CoproductRuntime(
          generation: 1,
          scheduler: _loggingScheduler(log),
          transport: HttpTransport(
            client: _RecordingClient(log),
            requestTimeout: const Duration(seconds: 1),
          ),
          coreShutdown: () async => log.add('core-shutdown'),
          disposeForeground: () => log.add('foreground-disposed'),
          networkType: network(log),
        );
        runtime.start();
        await pumpEventQueue();
        expect(log, ['network-listen']);
        await runtime.shutdown();
        expect(log, [
          'network-listen',
          'foreground-disposed',
          'network-cancelled',
          'scheduler-stopped',
          'core-shutdown',
          'transport-closed',
        ]);
      },
    );

    test(
      'a foreground disposal that throws still closes network observation',
      () async {
        final log = <String>[];
        final runtime = CoproductRuntime(
          generation: 1,
          scheduler: _scheduler(() {}),
          transport: HttpTransport(
            client: _RecordingClient(log),
            requestTimeout: const Duration(seconds: 1),
          ),
          coreShutdown: () async => log.add('core-shutdown'),
          disposeForeground: () => throw StateError('dispose failed'),
          networkType: network(log),
        );
        runtime.start();
        await pumpEventQueue();
        await expectLater(runtime.shutdown(), throwsStateError);
        expect(log, contains('network-cancelled'));
        expect(log, contains('core-shutdown'));
      },
    );

    test('a resume binder that throws does not fail start, reports the '
        'error, and polling still starts', () async {
      var polls = 0;
      final errors = <Object>[];
      final controllers = <StreamController<Object?>>[];
      final networkType = NetworkTypeService(
        events: (epoch) {
          final controller = StreamController<Object?>.broadcast();
          controllers.add(controller);
          return controller.stream;
        },
        upsert: Future<AutoUpsert?>.value(),
        bindResume: (_) => throw StateError('bind failed'),
        onUnavailable: () {},
      );
      final runtime = CoproductRuntime(
        generation: 1,
        scheduler: _scheduler(() => polls++),
        transport: HttpTransport(
          client: _RecordingClient(<String>[]),
          requestTimeout: const Duration(seconds: 1),
        ),
        coreShutdown: () async {},
        networkType: networkType,
        onError: (error, stack) => errors.add(error),
      );

      expect(runtime.start, returnsNormally);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(polls, greaterThan(0), reason: 'polling still started');

      // The service subscribes before binding resume, so the throwing binder
      // costs only the resume rechecks and the listen is live
      expect(controllers, hasLength(1));
      expect(controllers.single.hasListener, isTrue);
      await expectLater(runtime.shutdown(), completes);
      expect(
        controllers.single.hasListener,
        isFalse,
        reason: 'close leaves nothing live',
      );
    });

    test('a resume binder and an error reporter that both throw do not fail '
        'start', () async {
      var polls = 0;
      final runtime = CoproductRuntime(
        generation: 1,
        scheduler: _scheduler(() => polls++),
        transport: HttpTransport(
          client: _RecordingClient(<String>[]),
          requestTimeout: const Duration(seconds: 1),
        ),
        coreShutdown: () async {},
        networkType: NetworkTypeService(
          events: (epoch) => StreamController<Object?>.broadcast().stream,
          upsert: Future<AutoUpsert?>.value(),
          bindResume: (_) => throw StateError('bind failed'),
          onUnavailable: () {},
        ),
        onError: (_, _) => throw StateError('reporter exploded'),
      );

      expect(runtime.start, returnsNormally);
      expect(polls, greaterThan(0), reason: 'polling still started');
      await expectLater(runtime.shutdown(), completes);
    });
  });
}
