import 'dart:io';

import 'package:coproduct/src/sdk_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('User-Agent matches the pubspec version', () {
    final versionLine = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final version = versionLine.split(':')[1].trim();
    expect(coproductUserAgent, 'coproduct-flutter/$version');
  });
}
