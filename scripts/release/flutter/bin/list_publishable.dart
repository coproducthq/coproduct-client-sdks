// Print the relative path of every file pub would publish, one per line.
//
// The dry run resolves dependencies and writes .dart_tool, so it runs against a
// throwaway copy: callers use this to describe a canonical stage that must stay
// byte-identical between sealing and publication.
import 'dart:io';

import '../lib/pub_file_list.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: list_publishable.dart <stage-dir>');
    exit(2);
  }
  final probe = Directory.systemTemp.createTempSync('coproduct-list-probe');
  try {
    final probeStage = '${probe.path}/stage';
    final copy = Process.runSync('cp', ['-R', args.single, probeStage]);
    if (copy.exitCode != 0) {
      stderr.writeln('could not copy the stage: ${copy.stderr}');
      exit(1);
    }
    final dry = Process.runSync('flutter', ['pub', 'publish', '--dry-run'],
        workingDirectory: probeStage);
    final files = parsePubTranscript('${dry.stdout}\n${dry.stderr}');
    for (final f in files) {
      stdout.writeln(f);
    }
  } finally {
    probe.deleteSync(recursive: true);
  }
}
