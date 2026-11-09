// Keep internal plumbing out of the public barrels.
//
// Each name below resolves to the stand-in in internal_names.dart. If any
// public barrel starts exporting a declaration with the same name, the
// reference becomes ambiguous and this file fails to compile, so the test
// fails by name. Tests that need the real declarations import them from
// package:coproduct/src directly
import 'package:coproduct/coproduct.dart';
import 'package:coproduct/onboarding.dart';
import 'package:coproduct/paywall.dart';
import 'package:coproduct/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'internal_names.dart';

void main() {
  test('the paywall snapshot cache is not exported by any public barrel', () {
    // Touch one public name per barrel so none of the imports is unused
    expect(CoproductConfig, isNotNull);
    expect(CoproductOnboardingFlow, isNotNull);
    expect(CoproductPaywall, isNotNull);
    expect(CoproductTestHarness, isNotNull);

    expect(SnapshotCache, isNotNull);
    expect(snapshotCache, isNotNull);
    expect(snapshotCacheKey, isNotNull);
    expect(snapshotTtl, isNotNull);
  });
}
