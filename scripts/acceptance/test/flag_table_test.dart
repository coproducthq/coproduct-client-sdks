import 'package:coproduct_acceptance/flag_table.dart';
import 'package:test/test.dart';

void main() {
  test('the table has the sixteen expected flags', () {
    final keys = kFlagTable.map((f) => f.key).toList();
    expect(keys, [
      'fetch-control',
      'auto-platform',
      'auto-app-version',
      'auto-app-build',
      'auto-device-type',
      'auto-os-version',
      'auto-locale',
      'auto-timezone',
      'auto-session-count',
      'auto-first-seen-at-floor',
      'auto-first-seen-at-ceiling',
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

  test('no targeted row serves the same value on a match and a miss', () {
    for (final f in kFlagTable.where((f) => f.kind != FlagKind.untargeted)) {
      // A row whose variations agree would pass whether or not its rule matched
      expect(f.variationTarget, isNot(equals(f.variationMiss)),
          reason: '${f.key} variation target vs miss');
      // Only the integer getter truncates, so every other getter must return
      // exactly the stored variation
      if (f.getter != GetterType.integer) {
        expect(f.getterTarget, equals(f.variationTarget),
            reason: '${f.key} getter target vs variation target');
        expect(f.getterMiss, equals(f.variationMiss),
            reason: '${f.key} getter miss vs variation miss');
      }
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

  test('the session rows take their values from the runner', () {
    FlagSpec row(String key) => kFlagTable.singleWhere((f) => f.key == key);
    expect(row('auto-session-count').attribute, 'session_count');
    expect(row('auto-session-count').operator, 'equals');
    expect(row('auto-session-count').values, [kSessionCountToken]);
    expect(row('auto-first-seen-at-floor').attribute, 'first_seen_at');
    expect(row('auto-first-seen-at-floor').operator, 'gte');
    expect(row('auto-first-seen-at-floor').values, [kFirstSeenFloorToken]);
    expect(row('auto-first-seen-at-ceiling').attribute, 'first_seen_at');
    expect(row('auto-first-seen-at-ceiling').operator, 'lt');
    expect(row('auto-first-seen-at-ceiling').values, [kFirstSeenCeilingToken]);
  });
}
