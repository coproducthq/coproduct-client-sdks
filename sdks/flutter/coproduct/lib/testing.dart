/// Test support for widget tests that read Coproduct flags.
///
/// [CoproductTestHarness] gives you a real `CoproductClient` backed by values
/// you set in the test, with no SDK key and no network. See the testing guide
/// at
/// https://github.com/coproducthq/coproduct-client-sdks/blob/main/sdks/flutter/coproduct/doc/testing.md
library;

export 'src/testing/harness.dart' show CoproductTestHarness;
