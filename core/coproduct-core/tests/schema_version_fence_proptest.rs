use coproduct_core::error::InitError;
use coproduct_core::snapshot::{SUPPORTED_SCHEMA_VERSION, check_envelope_schema_version};
use proptest::prelude::*;

proptest! {
    #[test]
    fn any_non_one_body_version_rejects_without_full_body_parse(
        version in any::<u32>().prop_filter("must not equal supported", |v| *v != SUPPORTED_SCHEMA_VERSION),
    ) {
        // The snapshot body carries the random `schemaVersion` but is OTHERWISE
        // structurally invalid as a full `Snapshot`: it omits the required
        // `version` field and includes a `flags` value of the wrong type. A
        // correct fence pre-parses only `schemaVersion`, detects the mismatch,
        // and returns UnsupportedSchemaVersion. A buggy fence that deserializes
        // the full Snapshot first would surface a parse error instead, which
        // this proptest catches
        let raw = format!(
            r#"{{"snapshot":{{"schemaVersion":{version},"flags":42,"segments":"not-an-array"}}}}"#
        );

        match check_envelope_schema_version(&raw) {
            Err(InitError::UnsupportedSchemaVersion { actual, supported }) => {
                prop_assert_eq!(actual, version);
                prop_assert_eq!(supported, SUPPORTED_SCHEMA_VERSION);
            }
            Err(other) => {
                prop_assert!(false, "fence did not short-circuit before full body parse. Expected UnsupportedSchemaVersion, got {:?}", other);
            }
            Ok(_) => {
                prop_assert!(false, "version {version} should not have been accepted");
            }
        }
    }

    #[test]
    fn version_one_body_with_well_formed_envelope_always_accepts(
        inner_version in 0u32..1_000_000u32,
    ) {
        let raw = format!(r#"{{"snapshot":{{"schemaVersion":1,"version":{inner_version}}}}}"#);
        let body = check_envelope_schema_version(&raw).expect("schemaVersion 1 must accept");
        let expected = format!("\"version\":{inner_version}");
        prop_assert!(body.get().contains(&expected));
    }
}
