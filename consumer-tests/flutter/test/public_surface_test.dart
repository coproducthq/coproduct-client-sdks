// Pin the published public surface, from the installed package.
//
// Every other archive-backed gate exercises behaviour through a handful of
// entry points, so a promised export can disappear and nothing notices: the
// package still analyzes, the SDK's own unit tests still pass because several
// of them import `package:coproduct/src/...` directly and bypass the barrel,
// and no consumer names the missing symbol. A 1.0.0 missing part of its
// advertised API would clear every release gate.
//
// This imports ONLY the two public barrels — never `src/` — and names every
// declaration they promise. Referencing a type is enough: if an export is
// dropped, this file stops compiling and the gate fails by name.
//
// When the public surface changes deliberately, this file changes with it.
// That is the point: removing a line here is a visible decision rather than a
// silent regression.
import 'package:coproduct/coproduct.dart';
import 'package:coproduct/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package:coproduct/coproduct.dart exports its whole promised surface', () {
    // Client and entry point
    expect(CoproductClient, isNotNull);
    expect(Coproduct, isNotNull);

    // Configuration and values
    expect(CoproductConfig, isNotNull);
    expect(AttributeValue, isNotNull);
    expect(ProviderState, isNotNull);
    expect(FlagObservation, isNotNull);

    // Widgets
    expect(CoproductFlagBuilder, isNotNull);
    expect(CoproductScope, isNotNull);

    // The error hierarchy, every member. These are what an adopter catches, so
    // a missing one is a compile break in their app, discovered after release
    expect(CoproductException, isNotNull);
    expect(InvalidTargetingKey, isNotNull);
    expect(MissingSdkKey, isNotNull);
    expect(InvalidKeyType, isNotNull);
    expect(MalformedSdkKey, isNotNull);
    expect(InvalidConfig, isNotNull);
    expect(UnsupportedSchemaVersion, isNotNull);
    expect(CoproductAlreadyInitialized, isNotNull);
    expect(CoproductInitializationCancelled, isNotNull);
  });

  test('package:coproduct/testing.dart exports its promised surface', () {
    expect(CoproductTestHarness, isNotNull);
  });

  test('the exported types are usable, not merely named', () {
    // A type can be exported and still be wrong. Constructing the harness and
    // reading through the production client is the cheapest end-to-end proof
    // that the surface is real, and it needs no device.
    final harness = CoproductTestHarness();
    addTearDown(harness.shutdown);

    final CoproductClient client = harness.client;
    harness.setBool('surface-check', true);
    expect(client.getBool('surface-check', false), isTrue);

    expect(ProviderState.values, contains(ProviderState.ready));
    expect(const InvalidConfig('field', 'reason'), isA<CoproductException>());
  });
}
