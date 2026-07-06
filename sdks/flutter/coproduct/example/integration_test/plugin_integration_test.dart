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
