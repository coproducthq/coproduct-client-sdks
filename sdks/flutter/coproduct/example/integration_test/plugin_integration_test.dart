// Integration test for the Coproduct Flutter scaffold. Runs in a full Flutter
// app on a device/simulator, so it exercises the real Rust core through FRB.
// This is the runnable form of the demo's on-screen indicators and is the
// natural assertion for a CI consumer smoke test.

import 'dart:convert';

import 'package:coproduct/coproduct.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initialize, host callbacks, getBool, observer round-trip',
      (WidgetTester tester) async {
    final client = await Coproduct.initialize(sdkKey: 'cpk_mob_test_scaffold');

    // Rust invoked the Dart-hosted Transport and SecureStore during initialize.
    expect(mockTransport.requestCount, 1);
    expect(mockSecureStore.completedHandshake, isTrue);

    // Sync getter returns the scaffold stub default.
    expect(client.getBool('test-flag', false), isFalse);

    // Cache state is a bool regardless of whether a prior run wrote the snapshot.
    expect(client.wasLoadedFromCache(), isA<bool>());

    // Observer callback round-trips back through the FFI boundary.
    var observed = false;
    await client.observe('test-flag', false, (_) => observed = true);
    await client.simulateChange('test-flag', true);
    expect(observed, isTrue);
  });

  testWidgets('computeBucket matches all golden vectors',
      (WidgetTester tester) async {
    await Coproduct.initialize(sdkKey: 'cpk_mob_test_scaffold');

    final raw =
        await rootBundle.loadString('assets/bucketing_vectors.json');
    final vectors = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>();

    expect(vectors.length, 4, reason: 'expected 4 vectors in fixture');

    for (final v in vectors) {
      final actual = Coproduct.computeBucket(
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
