# Testing widgets that read flags

`package:coproduct/testing.dart` gives you a real `CoproductClient` backed by
values you set in the test. No SDK key, no network, no native library.

```dart
import 'package:coproduct/coproduct.dart';
import 'package:coproduct/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the new checkout appears when the flag is on', (tester) async {
    final harness = CoproductTestHarness()..setBool('new-checkout', false);
    addTearDown(harness.shutdown);

    await tester.pumpWidget(MaterialApp(
      home: CoproductScope(
        client: harness.client,
        child: const CheckoutPage(),
      ),
    ));
    expect(find.byType(OldCheckout), findsOneWidget);

    harness.setBool('new-checkout', true);
    await tester.pumpAndSettle();
    expect(find.byType(NewCheckout), findsOneWidget);
  });
}
```

`harness.client` is a genuine `CoproductClient`. Pass it to `CoproductScope`, to
a builder's `client:`, or to your own code that takes one.

## The harness supplies values, not targeting

**It does not evaluate targeting rules**, segments, prerequisites, rollouts, or
bucketing. Those live in the SDK's Rust core and are tested there.

So set the result your scenario needs:

```dart
// Not "this user matches the paid-plan rule". Just "this flag is on now"
harness.setBool('new-checkout', true);
```

If your widget behaves differently for different users, identify first and then
set the value that scenario should see:

```dart
await harness.client.identify(userId: 'paid-user');
harness.setBool('new-checkout', true);
await tester.pumpAndSettle();
```

An identity call never changes a flag value here. That is deliberate: a test that
appeared to evaluate rules would prove something the harness cannot actually
guarantee.

## Setting values

```dart
harness.setBool('flag', true);
harness.setString('greeting', 'hello');
harness.setNumber('max-items', 42.75);
harness.setJson('config', {'theme': 'dark'});
harness.removeFlag('greeting');
```

There is no `setInt`. The SDK has four flag types, and an integer read is a
projection of a number, so `setNumber('max-items', 42.75)` makes `getInt` return
`42` and `getNumber` return `42.75`, exactly as production does.

`removeFlag` makes the flag unavailable, so every observation of it falls back to
the default each caller passed. That is different from an available JSON null,
which `setJson('config', null)` stores.

`setNumber` rejects a non-finite value and `setJson` rejects anything JSON cannot
encode, both with `ArgumentError`, rather than letting a typo become a silently
missing flag.

## Pumping

Use `pumpAndSettle` after changing a value:

```dart
harness.setBool('new-checkout', true);
await tester.pumpAndSettle();
```

A single `pump()` is not enough. Delivery is asynchronous, matching production,
and the test binding checks whether a frame is already scheduled *before* it
flushes microtasks — so a value set by the test arrives after that check and is
drawn only by the following pump.

If the widget under test contains a continuous animation that prevents settling,
flush one delivery instead:

```dart
harness.setBool('new-checkout', true);
await tester.pump(Duration.zero);
```

When several changes land before a single frame, only the latest is rendered.
That is convergence, not lost delivery: the API reports current flag state rather
than a transition log.

## Provider state

The harness reports `ProviderState.ready` by default, so ordinary tests need no
setup. To exercise a loading or failure path:

```dart
harness.setProviderState(ProviderState.notReady);
expect(harness.client.state, ProviderState.notReady);
```

Provider-state changes are visible immediately, with no pump, because `state` is
a plain getter.

## Asserting on identity

The harness reports what your code sent, which is useful for testing sign-in
flows:

```dart
await harness.client.identify(
  userId: 'u1',
  attributes: {'plan': const AttributeValue.string('pro')},
);

expect(harness.targetingKey, 'u1');
expect(harness.developerAttributes,
    {'plan': const AttributeValue.string('pro')});
```

This is inspection of what you supplied, after reserved names are dropped. It is
not the production evaluation context: the core normalizes `locale`, `country`,
`continent`, `region_code`, `os_version`, and `app_version` before storing them,
and the harness deliberately does not reproduce that.

## Shutdown

`addTearDown(harness.shutdown)` closes every observation the test created.

Afterward the retained client's getters serve their defaults and observations
stop updating, matching what the SDK does after `Coproduct.shutdown()`. A harness
setter called after shutdown throws a `StateError`, so a test that mutates dead
state says so instead of quietly doing nothing.
