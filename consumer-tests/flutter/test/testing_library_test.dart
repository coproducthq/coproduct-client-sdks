// Exercise the published testing library from the installed package.
//
// Every other gate reaches the SDK through package:coproduct/coproduct.dart, so
// lib/testing.dart ships entirely unexercised: gutting it to an empty barrel
// stays valid Dart, keeps the file count at 140, keeps every hash and symbol
// check green, and ships a 1.0.0 whose advertised testing API does not exist.
//
// The harness is pure Dart over an in-memory backend, so this needs no device
// and runs as an ordinary widget test against the archive-installed package.
import 'package:coproduct/coproduct.dart';
import 'package:coproduct/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the published testing library exposes a usable harness', () {
    final harness = CoproductTestHarness();
    addTearDown(harness.shutdown);

    // .client must be a real CoproductClient, not a stand-in: the whole point
    // of the harness is that widget tests exercise the production type
    final CoproductClient client = harness.client;

    expect(client.getBool('missing-flag', false), isFalse,
        reason: 'an unset flag resolves to the default');

    harness.setBool('billing-v2', true);
    expect(client.getBool('billing-v2', false), isTrue,
        reason: 'setBool is visible through the production client');

    harness.setString('tier', 'pro');
    expect(client.getString('tier', 'free'), 'pro');

    harness.removeFlag('billing-v2');
    expect(client.getBool('billing-v2', false), isFalse,
        reason: 'a removed flag reverts to the default');
  });

  test('the harness drives observations and provider state', () async {
    final harness = CoproductTestHarness();
    addTearDown(harness.shutdown);

    final observation = harness.client.observeBool('dark-mode', false);
    addTearDown(observation.dispose);

    expect(observation.value, isFalse, reason: 'seeds synchronously');

    harness.setBool('dark-mode', true);
    await Future<void>.delayed(Duration.zero);
    expect(observation.value, isTrue);

    harness.setProviderState(ProviderState.ready);
    expect(harness.client.state, ProviderState.ready);
  });
}
