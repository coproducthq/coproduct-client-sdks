import 'dart:convert';

import 'package:coproduct/coproduct.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Coproduct.shutdown();
  });

  testWidgets('serves targeted values proving identity and auto attributes',
      (tester) async {
    const endpoint = String.fromEnvironment('COPRODUCT_ENDPOINT');
    const key = String.fromEnvironment('COPRODUCT_SDK_KEY');
    const expectedRaw = String.fromEnvironment('COPRODUCT_EXPECTED');
    expect(endpoint, isNotEmpty, reason: 'runner must pass COPRODUCT_ENDPOINT');
    expect(key, isNotEmpty, reason: 'runner must pass COPRODUCT_SDK_KEY');
    final expected =
        (jsonDecode(expectedRaw) as List).cast<Map<String, dynamic>>();
    // Fail red if the expected table is degenerate or short, so an empty or
    // truncated table cannot pass green having proven nothing about the flags
    // Twelve is the flag count locked by the host flag_table_test
    expect(expected, hasLength(12),
        reason: 'the runner must pass all twelve flag expectations');

    final client = await Coproduct.initialize(
      sdkKey: key,
      config: CoproductConfig(
        endpoint: Uri.parse(endpoint),
        startupTimeout: const Duration(seconds: 10),
      ),
    );
    // A unique key means a cold cache, so Ready proves a real first poll against
    // the fixture rather than a stale snapshot
    expect(client.state, ProviderState.ready);

    Object? read(Map<String, dynamic> row) {
      final flagKey = row['key'] as String;
      final def = row['callerDefault'];
      return switch (row['getter'] as String) {
        'boolean' => client.getBool(flagKey, def as bool),
        'string' => client.getString(flagKey, def as String),
        'integer' => client.getInt(flagKey, def as int),
        'number' => client.getNumber(flagKey, (def as num).toDouble()),
        'json' => client.getJson(flagKey, def),
        _ => throw StateError('unknown getter ${row['getter']}'),
      };
    }

    // Before identify: the fetch control and every auto flag resolve to their
    // target, and every identity flag falls through to its miss
    for (final row in expected) {
      final want = row['kind'] == 'identity' ? row['miss'] : row['target'];
      expect(read(row), want, reason: 'pre-identify ${row['key']}');
    }

    await client.identify(
      userId: 'acceptance-user',
      attributes: {'plan': const AttributeValue.string('pro')},
    );

    // After identify: every flag resolves to its target, proving both identity
    // targeting and that the automatic layer survived identity replacement
    for (final row in expected) {
      expect(read(row), row['target'], reason: 'post-identify ${row['key']}');
    }
  });
}
