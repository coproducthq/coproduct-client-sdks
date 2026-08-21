// Assert that every file naming the package version agrees with the pubspec.
//
// prepareRelease() already audits this, but it runs when the version is bumped,
// not when the package ships. Nothing between those two points re-checks it, so
// a hand-edit to any one of the four files publishes a disagreement. The
// podspec version is the costly one: it is externally visible in every
// consumer's Podfile.lock and cannot be withdrawn.
import 'dart:io';

import '../lib/prepare.dart';

void main(List<String> args) {
  final repoRoot = args.isNotEmpty
      ? args.first
      : Directory.current.parent.parent.path;
  final pkgDir = '$repoRoot/sdks/flutter/coproduct';

  final pubspecPath = '$pkgDir/pubspec.yaml';
  final pubspec = File(pubspecPath).readAsStringSync();

  // The pubspec is the reference the other three are checked against, so read
  // the version from it rather than taking one on the command line: a version
  // passed in could agree with nothing on disk and still pass
  final match =
      RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(pubspec);
  if (match == null) {
    stderr.writeln('ERROR: no version line in $pubspecPath');
    exit(1);
  }
  final version = match.group(1)!;

  final issues = auditIdentity(
    pubspec: pubspec,
    sdkVersion: File('$pkgDir/lib/src/sdk_version.dart').readAsStringSync(),
    readme: File('$pkgDir/README.md').readAsStringSync(),
    podspec: File('$pkgDir/ios/coproduct.podspec').readAsStringSync(),
    version: version,
  );

  if (issues.isNotEmpty) {
    stderr.writeln('ERROR: the package version is not coherent at $version:');
    for (final i in issues) {
      stderr.writeln('  $i');
    }
    exit(1);
  }
  stdout.writeln('version coherent at $version');
  stdout.writeln('COPRODUCT_FLUTTER_IDENTITY_STATUS pass=true');
}
