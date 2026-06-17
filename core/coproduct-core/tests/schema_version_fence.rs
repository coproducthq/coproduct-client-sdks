use coproduct_core::error::InitError;
use coproduct_core::snapshot::{SUPPORTED_SCHEMA_VERSION, check_envelope_schema_version};

#[test]
fn matching_version_returns_ok_and_raw_body() {
    let raw = r#"{"snapshot":{"schemaVersion":1,"version":47}}"#;
    let body = check_envelope_schema_version(raw).expect("should accept v1");
    assert!(body.get().contains("\"version\":47"));
}

#[test]
fn mismatched_version_returns_unsupported() {
    let raw = r#"{"snapshot":{"schemaVersion":2,"version":47}}"#;
    let err = check_envelope_schema_version(raw).expect_err("should reject v2");
    match err {
        InitError::UnsupportedSchemaVersion { actual, supported } => {
            assert_eq!(actual, 2);
            assert_eq!(supported, SUPPORTED_SCHEMA_VERSION);
        }
        other => panic!("expected UnsupportedSchemaVersion, got {other:?}"),
    }
}

#[test]
fn missing_schema_version_field_returns_parse_error() {
    let raw = r#"{"snapshot":{"version":47}}"#;
    assert!(check_envelope_schema_version(raw).is_err());
}

#[test]
fn malformed_envelope_returns_error() {
    let raw = r#"{"snapshot": "not-an-object"}"#;
    // The envelope shape parses but the snapshot body is the wrong shape. The
    // fence pre-parse looks for `schemaVersion` inside the body and returns an
    // error when the body cannot supply it
    assert!(check_envelope_schema_version(raw).is_err());
}
