import 'dart:io';

import 'package:coproduct_release/prepare.dart';

// dart run bin/prepare_release.dart --version 0.1.0 --date 2026-08-04
// Run from the repo root. Transforms the four coordinated release files of the
// Flutter package from 0.1.0-dev to the release version as coordinated writes,
// with input validation, best-effort rollback on write failure, idempotence, and
// an identity audit
Future<void> main(List<String> args) async {
  final opts = _parse(args);
  final version = opts['version'];
  final date = opts['date'];
  if (version == null || date == null) {
    stderr.writeln('usage: prepare_release.dart --version <v> --date <YYYY-MM-DD>');
    exit(2);
  }
  // Resolve the package dir from this script's own location so the command works
  // from any working directory: bin -> release -> scripts -> repo root
  final scriptDir = File.fromUri(Platform.script).parent;
  final repoRoot = scriptDir.parent.parent.parent.path;
  try {
    prepareRelease(
        pkgDir: '$repoRoot/sdks/flutter/coproduct', version: version, date: date);
  } on ReleasePrepError catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
  stdout.writeln('prepared release $version ($date); identity audit clean');
}

Map<String, String> _parse(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (args[i].startsWith('--')) map[args[i].substring(2)] = args[i + 1];
  }
  return map;
}
