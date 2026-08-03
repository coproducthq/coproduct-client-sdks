import 'dart:async';
import 'dart:io';

// Ignores SIGTERM and spawns a grandchild that sleeps, so a naive single-PID
// kill leaves the grandchild alive. Prints both PIDs so the test can watch them
Future<void> main() async {
  ProcessSignal.sigterm.watch().listen((_) {});
  final grandchild = await Process.start('sleep', ['600']);
  stdout.writeln('CHILD=$pid GRANDCHILD=${grandchild.pid}');
  await Completer<void>().future;
}
