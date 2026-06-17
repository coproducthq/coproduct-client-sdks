use coproduct_core::error::InitError;

#[test]
fn invalid_key_type_renders_prefix() {
    let err = InitError::InvalidKeyType {
        prefix: "cpk_dsh_".into(),
    };
    let rendered = format!("{err}");
    assert!(rendered.contains("cpk_mob_"));
    assert!(rendered.contains("cpk_dsh_"));
}

#[test]
fn missing_sdk_key_has_actionable_message() {
    let err = InitError::MissingSdkKey;
    let rendered = format!("{err}");
    assert!(rendered.to_lowercase().contains("sdk key"));
}

#[test]
fn invalid_config_carries_field_and_reason() {
    let err = InitError::InvalidConfig {
        field: "pollInterval".into(),
        reason: "must be >= 30s".into(),
    };
    let rendered = format!("{err}");
    assert!(rendered.contains("pollInterval"));
    assert!(rendered.contains("must be >= 30s"));
}

#[test]
fn unsupported_schema_version_carries_actual_and_supported() {
    let err = InitError::UnsupportedSchemaVersion {
        actual: 2,
        supported: 1,
    };
    let rendered = format!("{err}");
    assert!(rendered.contains("2"));
    assert!(rendered.contains("1"));
}

#[test]
fn malformed_sdk_key_carries_actionable_reason() {
    let err = InitError::MalformedSdkKey {
        reason: "expected 40 characters total, got 8".into(),
    };
    let rendered = format!("{err}");
    assert!(rendered.to_lowercase().contains("malformed"));
    assert!(rendered.contains("40 characters"));
}
