import 'dart:async';
import 'dart:io';

// Records its pid to the file at args[0] and hangs, so a signal test can locate
// the process the runner started and later confirm the runner killed it. With a
// second arg 'ready' it first emits the readiness record, taking the fixture
// role. Exits on SIGTERM so the runner's teardown reclaims it promptly
Future<void> main(List<String> args) async {
  ProcessSignal.sigterm.watch().listen((_) => exit(0));
  File(args[0]).writeAsStringSync('$pid');
  if (args.length > 1 && args[1] == 'ready') {
    stdout.writeln('COPRODUCT_FIXTURE_READY port=54321');
    await stdout.flush();
  }
  await Completer<void>().future;
}
