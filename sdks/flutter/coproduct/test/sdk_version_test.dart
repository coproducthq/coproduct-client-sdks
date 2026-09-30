import 'dart:io';

import 'package:coproduct/src/sdk_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('User-Agent matches the pubspec version', () {
    expect(coproductUserAgent, 'coproduct-flutter/${_pubspecVersion()}');
  });

  test('the podspec version matches the pubspec version', () {
    // The podspec version is externally visible in a consumer's Podfile.lock.
    // The release tool keeps the two in agreement, but it only runs at release
    // time, so ordinary development would drift undetected without this
    final podspec = File('ios/coproduct.podspec').readAsStringSync();
    expect(podspec, contains("s.version          = '${_pubspecVersion()}'"));
  });
}

String _pubspecVersion() {
  final versionLine = File(
    'pubspec.yaml',
  ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
  return versionLine.split(':')[1].trim();
}
