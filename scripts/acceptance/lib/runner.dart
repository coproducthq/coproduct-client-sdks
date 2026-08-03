import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'process_tree.dart';

/// No test exit code exists in these cases, so the runner returns a dedicated
/// nonzero code per cause.
const int kCodeStartupTimeout = 10;
const int kCodeFixtureCrashed = 11;
const int kCodeOverallTimeout = 12;

/// The run otherwise succeeded but teardown left a live process tree behind, so
/// the run must not report success.
const int kCodeTeardownIncomplete = 13;

/// Caps the retained fixture log so a chatty or wedged fixture cannot grow the
/// buffer without bound over a long run. The tail is what a failure report needs.
const int _kMaxFixtureLogLines = 500;

/// The endpoint host the app uses to reach the loopback fixture, per platform.
Uri endpointFor(String platform, int port) => switch (platform) {
      'ios' => Uri.parse('http://127.0.0.1:$port'),
      'android' => Uri.parse('http://10.0.2.2:$port'),
      _ => throw ArgumentError('unknown platform $platform'),
    };

/// Extracts the fixture's port from its single readiness record.
int? parseFixturePort(String line) {
  final m =
      RegExp(r'^COPRODUCT_FIXTURE_READY port=(\d+)$').firstMatch(line.trim());
  return m == null ? null : int.parse(m.group(1)!);
}

/// Starts the fixture, waits for its readiness record, runs the test command
/// against the fixture endpoint, and tears the whole tree down on every exit
/// path. Returns the test's exit code, or a dedicated nonzero code when there is
/// no test exit code. Commands are injected so the orchestration is testable.
///
/// An interrupt (SIGINT or SIGTERM) is turned into a pending result rather than
/// an immediate exit, so an in-flight child spawn is always awaited and captured
/// before teardown, there is a single return path, and only the top-level
/// entrypoint decides to exit the process.
Future<int> runAcceptance({
  required List<String> fixtureCommand,
  required List<String> Function(Uri endpoint) testCommandForEndpoint,
  required Uri Function(int port) endpointForPort,
  required String testWorkingDirectory,
  required Duration readinessTimeout,
  required Duration overallTimeout,
  required void Function(String) log,
  Duration teardownGrace = const Duration(seconds: 5),
}) async {
  final fixtureLogs = <String>[];
  void recordFixtureLog(String line) {
    fixtureLogs.add(line);
    if (fixtureLogs.length > _kMaxFixtureLogLines) fixtureLogs.removeAt(0);
  }

  Process? fixture;
  Process? test;
  var teardownIncomplete = false;

  // An interrupt completes this with its exit code rather than exiting the
  // process, so the flow can finish any in-flight spawn, tear down once, and
  // return the code. Only the entrypoint exits
  final interrupted = Completer<int>();

  // A shared future rather than a done-flag, so a second caller awaits the same
  // teardown to completion instead of returning while it is still in flight. It
  // attempts both trees even if the first reports survivors, and records an
  // incomplete teardown so the run cannot report success with a process still up
  Future<void>? cleanupFuture;
  Future<void> cleanup() => cleanupFuture ??= () async {
        Future<void> killTracked(Process? p) async {
          if (p == null) return;
          try {
            await killProcessTree(p.pid, graceWindow: teardownGrace);
          } catch (error) {
            teardownIncomplete = true;
            log('teardown did not fully terminate a process tree: $error');
          }
        }

        await killTracked(test);
        await killTracked(fixture);
      }();

  final signals = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) {
      if (!interrupted.isCompleted) interrupted.complete(130);
    }),
    ProcessSignal.sigterm.watch().listen((_) {
      if (!interrupted.isCompleted) interrupted.complete(143);
    }),
  ];

  // Runs the orchestration and returns the outcome code. Assigns the outer
  // fixture and test handles as soon as each spawn completes, so cleanup can
  // always reach a just-started child even when an interrupt raced the spawn
  Future<int> runFlow() async {
    if (interrupted.isCompleted) return interrupted.future;

    final f =
        await Process.start(fixtureCommand.first, fixtureCommand.sublist(1));
    fixture = f;
    final fixtureExited = Completer<int>();
    unawaited(f.exitCode.then((c) {
      if (!fixtureExited.isCompleted) fixtureExited.complete(c);
    }));
    f.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(recordFixtureLog);

    final portCompleter = Completer<int?>();
    final readinessSub = f.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) {
      final p = parseFixturePort(l);
      if (p != null) {
        if (!portCompleter.isCompleted) portCompleter.complete(p);
      } else if (l.trim().isNotEmpty) {
        // The fixture writes only the readiness record to stdout, so anything
        // else there is anomalous. Surface it immediately rather than leaving a
        // silent wait, without treating it as fatal
        log('fixture stdout before readiness (ignored): $l');
      }
    });
    final port = await Future.any<int?>([
      portCompleter.future,
      fixtureExited.future.then((_) => null),
      Future.delayed(readinessTimeout, () => null),
      interrupted.future.then((_) => null),
    ]);
    // Keep draining the fixture stdout after readiness so a fixture that logs
    // there cannot deadlock on pipe backpressure
    readinessSub.onData((_) {});
    if (interrupted.isCompleted) return interrupted.future;
    if (port == null) {
      if (fixtureExited.isCompleted) {
        log('fixture exited before readiness; logs:\n${fixtureLogs.join('\n')}');
        return kCodeFixtureCrashed;
      }
      log('fixture did not report readiness within $readinessTimeout; '
          'logs:\n${fixtureLogs.join('\n')}');
      return kCodeStartupTimeout;
    }

    final cmd = testCommandForEndpoint(endpointForPort(port));
    final t = await Process.start(cmd.first, cmd.sublist(1),
        workingDirectory: testWorkingDirectory);
    test = t;
    if (interrupted.isCompleted) return interrupted.future;
    t.stdout.transform(utf8.decoder).listen(stdout.write);
    t.stderr.transform(utf8.decoder).listen(stderr.write);
    final testExited = Completer<int>();
    unawaited(t.exitCode.then((c) {
      if (!testExited.isCompleted) testExited.complete(c);
    }));

    final outcome = await Future.any<int>([
      testExited.future,
      fixtureExited.future.then((_) => kCodeFixtureCrashed),
      Future.delayed(overallTimeout, () => kCodeOverallTimeout),
      interrupted.future,
    ]);
    if (outcome == kCodeFixtureCrashed && !testExited.isCompleted) {
      log('fixture exited during the test; logs:\n${fixtureLogs.join('\n')}');
    } else if (outcome == kCodeOverallTimeout && !testExited.isCompleted) {
      log('test did not complete within $overallTimeout');
    }
    return outcome;
  }

  late final int outcome;
  try {
    outcome = await runFlow();
  } finally {
    await cleanup();
    for (final s in signals) {
      await s.cancel();
    }
  }
  // A late interrupt that arrived after the flow had already selected an exit
  // code, for example during cleanup, takes priority over a successful result,
  // and is read only after the signal subscriptions are cancelled so the
  // captured code is final
  if (interrupted.isCompleted) return interrupted.future;
  // A clean run that nonetheless left a live process tree must not report
  // success, so a leak is visible in the exit code, not only the log
  if (outcome == 0 && teardownIncomplete) return kCodeTeardownIncomplete;
  return outcome;
}
