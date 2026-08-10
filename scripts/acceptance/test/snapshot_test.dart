import 'package:coproduct_acceptance/flag_table.dart';
import 'package:coproduct_acceptance/snapshot.dart';
import 'package:test/test.dart';

Map<String, Object?> _flag(Map<String, Object?> env, String key) {
  final snap = env['snapshot'] as Map<String, Object?>;
  final flags = (snap['flags'] as List).cast<Map<String, Object?>>();
  return flags.singleWhere((f) => f['key'] == key);
}

void main() {
  final env = buildSnapshotEnvelope(
    expectedPlatform: 'ios',
    appVersion: '1.0.0',
    appBuild: '1',
    generatedAt: '2026-08-01T00:00:00Z',
  );

  test('the envelope wraps the snapshot and omits sdkContext', () {
    expect(env.keys, ['snapshot']);
    final snap = env['snapshot'] as Map<String, Object?>;
    expect(snap['schemaVersion'], 1);
    expect(snap['version'], 1);
    expect(snap['environment'], <String, Object?>{});
    expect(snap['segments'], <Object?>[]);
    expect((snap['flags'] as List).length, 12);
  });

  test('the causality invariant holds for every targeted flag', () {
    for (final spec in kFlagTable.where((f) => f.kind != FlagKind.untargeted)) {
      final flag = _flag(env, spec.key);
      expect(flag['type'], spec.flagType);
      expect(flag['offVariation'], 'miss');
      expect(flag['fallthroughVariation'], 'miss');
      final rules = (flag['targetingRules'] as List).cast<Map<String, Object?>>();
      expect(rules, hasLength(1));
      final rule = rules.single;
      expect(rule['coverage'], 10000);
      expect(rule['rollout'], {'type': 'variation', 'variation': 'match'});
      final cond = rule['condition'] as Map<String, Object?>;
      expect(cond['type'], 'attribute');
      expect(cond.containsKey('values'), isTrue);
      expect(cond['values'], isA<List>());
    }
  });

  test('auto-platform targets the runner-supplied platform', () {
    final cond = ((_flag(env, 'auto-platform')['targetingRules'] as List).first
        as Map<String, Object?>)['condition'] as Map<String, Object?>;
    expect(cond['attribute'], 'platform');
    expect(cond['operator'], 'equals');
    expect(cond['values'], ['ios']);
  });

  test('is_set conditions carry an empty values array', () {
    final cond = ((_flag(env, 'auto-timezone')['targetingRules'] as List).first
        as Map<String, Object?>)['condition'] as Map<String, Object?>;
    expect(cond['operator'], 'is_set');
    expect(cond['values'], <String>[]);
  });

  test('the fetch-control flag is untargeted and falls through to fetched', () {
    final flag = _flag(env, 'fetch-control');
    expect(flag['targetingRules'], <Object?>[]);
    expect(flag['fallthroughVariation'], 'on');
    final variations = (flag['variations'] as List).cast<Map<String, Object?>>();
    expect(variations.singleWhere((v) => v['key'] == 'on')['value'], 'fetched');
  });

  test('the integer flag stores a fractional number variation', () {
    final flag = _flag(env, 'identity-int');
    expect(flag['type'], 'NUMBER');
    final variations = (flag['variations'] as List).cast<Map<String, Object?>>();
    expect(variations.singleWhere((v) => v['key'] == 'match')['value'], 42.75);
  });

  test('expectedTable projects getter-level expectations', () {
    final t = expectedTable();
    final intRow = t.singleWhere((r) => r['key'] == 'identity-int');
    expect(intRow['getter'], 'integer');
    expect(intRow['target'], 42);
    expect(intRow['miss'], 0);
    expect(intRow['callerDefault'], -1);
    expect(intRow['kind'], 'identity');
  });

  test('the envelope omits the requested flags and carries the version', () {
    final full = buildSnapshotEnvelope(
      expectedPlatform: 'ios',
      appVersion: '1.2.3',
      appBuild: '45',
      generatedAt: '2026-08-01T00:00:00Z',
    );
    final fullFlags =
        ((full['snapshot']! as Map)['flags']! as List).cast<Map<String, Object?>>();
    expect((full['snapshot']! as Map)['version'], 1,
        reason: 'the default reproduces the original envelope');

    final trimmed = buildSnapshotEnvelope(
      expectedPlatform: 'ios',
      appVersion: '1.2.3',
      appBuild: '45',
      generatedAt: '2026-08-01T00:00:00Z',
      version: 7,
      omitFlags: {'fetch-control'},
    );
    final trimmedFlags =
        ((trimmed['snapshot']! as Map)['flags']! as List).cast<Map<String, Object?>>();

    expect((trimmed['snapshot']! as Map)['version'], 7);
    expect(trimmedFlags.map((f) => f['key']), isNot(contains('fetch-control')));
    expect(trimmedFlags, hasLength(fullFlags.length - 1),
        reason: 'exactly the omitted flag is gone');
  });
}
