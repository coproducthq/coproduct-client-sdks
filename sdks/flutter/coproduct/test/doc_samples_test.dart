import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the recipes doc exists and the README points at it', () {
    expect(File('doc/state_management_recipes.md').existsSync(), isTrue);
    expect(File('README.md').readAsStringSync(),
        contains('doc/state_management_recipes.md'),
        reason: 'a recipe nobody can find is not documentation');
  });
}
