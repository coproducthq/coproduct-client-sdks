import 'package:coproduct_acceptance/flag_table.dart';
import 'package:test/test.dart';

void main() {
  test('the table has the twelve expected flags', () {
    final keys = kFlagTable.map((f) => f.key).toList();
    expect(keys, [
      'fetch-control',
      'auto-platform',
      'auto-app-version',
      'auto-app-build',
      'auto-os-version',
      'auto-locale',
      'auto-timezone',
      'identity-bool',
      'identity-string',
      'identity-int',
      'identity-number',
      'identity-json',
    ]);
  });

  test('every targeted flag has a three-way distinct target, miss, and default',
      () {
    for (final f in kFlagTable.where((f) => f.kind != FlagKind.untargeted)) {
      // bool is the documented exception: only two values exist, so default
      // equals miss and only the pre/post transition proves causality
      if (f.getter == GetterType.boolean) {
        expect(f.getterTarget, isNot(equals(f.getterMiss)),
            reason: '${f.key} target vs miss');
        continue;
      }
      final values = {f.getterTarget, f.getterMiss, f.callerDefault}
          .map((v) => v.toString())
          .toSet();
      expect(values.length, 3, reason: '${f.key} target/miss/default distinct');
    }
  });

  test('identity flags target the plan attribute and auto flags carry a rule',
      () {
    for (final f in kFlagTable.where((f) => f.kind == FlagKind.identity)) {
      expect(f.attribute, 'plan');
      expect(f.operator, 'equals');
      expect(f.values, ['pro']);
    }
    expect(kFlagTable.singleWhere((f) => f.key == 'auto-timezone').operator,
        'is_set');
    expect(kFlagTable.singleWhere((f) => f.key == 'auto-timezone').values,
        isEmpty);
  });
}
