import 'dart:async';

import 'package:coproduct/src/http_transport.dart';
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

void main() {
  test('start polls, shutdown tears down in order and stops the scheduler first',
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
          requestTimeout: const Duration(seconds: 1)),
      coreShutdown: () async {
        // The scheduler is already stopped, so a foreground here starts no poll,
        // and a triggered poll would increment synchronously, so no wait is needed
        final before = polls;
        scheduler.onForeground();
        expect(polls, before, reason: 'scheduler must be stopped before core');
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
  });

  test('a concurrent or reentrant second shutdown joins the first teardown',
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
          requestTimeout: const Duration(seconds: 1)),
      coreShutdown: () async {
        await gate.future;
        log.add('core-shutdown');
      },
      // A reentrant shutdown from within foreground disposal must join, not
      // start a second teardown
      disposeForeground: () {
        reentrantResult = identical(runtime.shutdown(), runtime.shutdown()) ? 1 : 0;
      },
    );
    runtime.start();
    final first = runtime.shutdown();
    final second = runtime.shutdown();
    gate.complete();
    await Future.wait([first, second]);
    expect(log.where((e) => e == 'core-shutdown').length, 1); // ran once
    expect(reentrantResult, 1); // the reentrant calls joined the same future
  });

  test('the transport is closed even if the core shutdown throws', () async {
    final log = <String>[];
    final runtime = CoproductRuntime(
      generation: 1,
      scheduler: _scheduler(() {}),
      transport: HttpTransport(
          client: _RecordingClient(log),
          requestTimeout: const Duration(seconds: 1)),
      coreShutdown: () async => throw StateError('latch failed'),
    );
    runtime.start();
    await expectLater(runtime.shutdown(), throwsA(isA<StateError>()));
    expect(log, contains('transport-closed'));
  });

  test('a foreground disposal failure does not skip the later stages', () async {
    final log = <String>[];
    final runtime = CoproductRuntime(
      generation: 1,
      scheduler: _scheduler(() {}),
      transport: HttpTransport(
          client: _RecordingClient(log),
          requestTimeout: const Duration(seconds: 1)),
      coreShutdown: () async => log.add('core-shutdown'),
      disposeForeground: () => throw StateError('foreground'),
    );
    runtime.start();
    await expectLater(runtime.shutdown(), throwsA(isA<StateError>()));
    // The core latch was still set and the transport still closed
    expect(log, ['core-shutdown', 'transport-closed']);
  });
}
