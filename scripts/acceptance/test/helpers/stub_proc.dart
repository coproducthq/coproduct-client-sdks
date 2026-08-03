import 'dart:async';
import 'dart:io';

// A parameterized stand-in for the fixture and the test command, so the runner
// orchestration is exercised without a device. It exits on SIGTERM so the
// runner's polite teardown reclaims it at once and the suite stays fast. SIGKILL
// escalation is covered separately by the process-tree tests
Future<void> main(List<String> args) async {
  // A bare Completer future does not keep a Dart isolate alive, so a signal
  // subscription holds the process open until the runner terminates it
  ProcessSignal.sigterm.watch().listen((_) => exit(0));
  final mode = args.isNotEmpty ? args[0] : 'hang';
  switch (mode) {
    case 'fixture-ready':
      stdout.writeln('COPRODUCT_FIXTURE_READY port=54321');
      await Completer<void>().future;
    case 'fixture-crash':
      stderr.writeln('boom');
      exit(1);
    case 'ready-then-exit':
      // Report readiness, then exit while the test is still running, so the
      // runner observes a mid-test fixture crash
      stdout.writeln('COPRODUCT_FIXTURE_READY port=54321');
      await Future<void>.delayed(Duration(milliseconds: int.parse(args[1])));
      exit(0);
    case 'bad-ready':
      // Emit a line that is not the readiness record and then hang, so the
      // runner sees malformed stdout and must fall back to the readiness timeout
      stdout.writeln('NOT-THE-READINESS-RECORD');
      await Completer<void>().future;
    case 'escaping-fixture':
      // Report readiness, spawn a child that ignores SIGTERM so it reparents out
      // of the tree when this process is torn down, and record its pid so the
      // test can prove teardown reported the escape and then clean it up
      final escaped = await Process.start(
          'sh', ['-c', 'trap "" TERM; while :; do sleep 1; done']);
      File(args[1]).writeAsStringSync('${escaped.pid}');
      stdout.writeln('COPRODUCT_FIXTURE_READY port=54321');
      await Completer<void>().future;
    case 'exit':
      exit(int.parse(args[1]));
    default:
      await Completer<void>().future;
  }
}
