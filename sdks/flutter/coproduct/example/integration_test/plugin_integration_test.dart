// Integration test for the Coproduct Flutter scaffold. Runs in a full Flutter
// app on a device/simulator, so it exercises the real Rust core through FRB.
// This is the runnable form of the demo's on-screen indicators and is the
// natural assertion for a CI consumer smoke test.

import 'dart:convert';

import 'package:coproduct/coproduct.dart';
import 'package:coproduct/src/rust/api.dart' show bucketForVectors;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Coproduct.shutdown();
  });

  testWidgets('initialize, read a default, identify, shut down',
      (WidgetTester tester) async {
    final client = await Coproduct.initialize(
        sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');

    // With no snapshot fixture, an unknown flag reads its default. The full
    // targeted-value acceptance against a device fixture is out of scope here
    expect(client.getBool('test-flag', false), isFalse);
    expect(client.state, isNotNull);

    await client.identify(userId: 'alice');
    expect(client.previousAnonymousId, isNotNull);
  });

  testWidgets('typed getters cross the ffi and return defaults for missing keys',
      (WidgetTester tester) async {
    final client = await Coproduct.initialize(
        sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');

    // initialize loads any persisted snapshot from the app cache, so a per-run
    // unique prefix keeps these default-path assertions independent of prior runs
    final k = 'cp-${DateTime.now().microsecondsSinceEpoch}-';

    expect(client.getString('${k}string', 'fallback'), 'fallback');
    expect(client.getNumber('${k}number', 3.5), 3.5);

    // Full signed-64-bit precision survives the FFI, including the extremes and a
    // value above 2^53. Dart permits the positive token 9223372036854775808 only
    // as the operand of unary minus, so the signed-64-bit minimum is a valid
    // negative expression, and its native int covers the signed 64-bit range
    expect(client.getInt('${k}int', 42), 42);
    expect(client.getInt('${k}int-max', 9223372036854775807), 9223372036854775807);
    expect(client.getInt('${k}int-min', -9223372036854775808), -9223372036854775808);
    expect(client.getInt('${k}int-big', 9007199254740993), 9007199254740993);

    // getJson encode/decode round trip on the default path: map, list, nested,
    // scalar, and null
    expect(
        client.getJson('${k}json-map', {
          'theme': 'system',
          'nested': {
            'items': [1, 2, 3]
          }
        }),
        {
          'theme': 'system',
          'nested': {
            'items': [1, 2, 3]
          }
        });
    expect(client.getJson('${k}json-list', [1, 'two', null]), [1, 'two', null]);
    expect(client.getJson('${k}json-scalar', 'hi'), 'hi');
    expect(client.getJson('${k}json-null', null), isNull);

    // An unencodable (cyclic) default returns the exact same instance without
    // throwing. Asserted with identical() because deep equality can recurse on a
    // cyclic structure
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;
    expect(identical(client.getJson('${k}json-cyclic', cyclic), cyclic), isTrue);
  });

  testWidgets('identity mutators cross the ffi and surface typed errors',
      (WidgetTester tester) async {
    final client = await Coproduct.initialize(
        sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');

    // Empty keys surface the public typed error, not a generated or bridge type
    await expectLater(client.identify(userId: ''),
        throwsA(isA<InvalidTargetingKey>()));
    await expectLater(client.setContext(targetingKey: ''),
        throwsA(isA<InvalidTargetingKey>()));

    // A rejected queued mutation does not block a later valid one
    final rejected = client.identify(userId: '');
    final accepted = client.identify(userId: 'alice');
    await expectLater(rejected, throwsA(isA<InvalidTargetingKey>()));
    await accepted;

    // The first linked identify captures previousAnonymousId (sync getter, no
    // future), and signOut clears it
    final captured = client.previousAnonymousId;
    expect(captured, isNotNull);
    await client.signOut();
    expect(client.previousAnonymousId, isNull);

    // Every AttributeValue variant encodes and decodes across the real bridge, and
    // a later linked identify recaptures the same original anonymous id
    await client.identify(userId: 'bob', attributes: {
      'plan': const AttributeValue.string('pro'),
      'seats': AttributeValue.number(5),
      'ratio': AttributeValue.number(1.5),
      'beta': const AttributeValue.bool(true),
      'roles': AttributeValue.stringList(['admin', 'editor']),
      'empty': AttributeValue.stringList(const []),
      'note': const AttributeValue.nullValue(),
    });
    expect(client.previousAnonymousId, captured);
    await client.updateAttributes({'plan': const AttributeValue.string('team')});
    await client.setContext(targetingKey: 'org-42', attributes: {
      'tier': const AttributeValue.string('gold'),
    });
    await client.removeAttributes(['tier']);
  });

  testWidgets('bucketForVectors matches all golden vectors',
      (WidgetTester tester) async {
    await Coproduct.initialize(sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');

    final raw =
        await rootBundle.loadString('assets/bucketing_vectors.json');
    final vectors = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>();

    expect(vectors.length, 4, reason: 'expected 4 vectors in fixture');

    for (final v in vectors) {
      final actual = bucketForVectors(
        ruleId: v['rule_id'] as String,
        targetingKey: v['targeting_key'] as String,
        suffix: v['suffix'] as String,
      );
      expect(
        actual,
        v['expected_bucket'],
        reason:
            'rule_id=${v['rule_id']} targeting_key=${v['targeting_key']} suffix=${v['suffix']}',
      );
    }
  });
}
