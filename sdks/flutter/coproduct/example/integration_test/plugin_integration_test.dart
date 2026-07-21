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

  testWidgets('initialize, host callbacks, getBool, observer registration',
      (WidgetTester tester) async {
    final client = await Coproduct.initialize(sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');

    // initialize no longer polls, so it does not invoke the Dart-hosted
    // Transport. The SecureStore is still exercised by the cold-start identity
    // read. Transport-bridge coverage returns once the binding exposes a poll
    // entry point and the scaffold drives a poll after initialize.
    expect(mockTransport.requestCount, 0);
    expect(mockSecureStore.completedHandshake, isTrue);

    // Sync getter returns the stub default.
    expect(client.getBool('test-flag', false), isFalse);

    // Observer registration succeeds and yields a live cancellable handle.
    final subscription = await client.observe('test-flag', false, (_) {});
    expect(subscription, isNotNull);
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
