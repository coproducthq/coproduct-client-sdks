use coproduct_core::client::CoproductClient;
use coproduct_core::details::{FlagEvaluationDetails, Reason};
use coproduct_core::snapshot::{Flag, FlagType, Snapshot, Variation, VariationValue};
use serde_json::json;

fn flag(key: &str, flag_type: FlagType, value: VariationValue) -> Flag {
    Flag {
        key: key.to_string(),
        r#type: flag_type,
        enabled: true,
        is_paused: false,
        variations: vec![Variation {
            key: "on".to_string(),
            value,
            name: None,
        }],
        off_variation: Some("on".to_string()),
        fallthrough_variation: Some("on".to_string()),
        targeting_rules: vec![],
        prerequisites: vec![],
        experiment: None,
    }
}

fn snap(flags: Vec<Flag>) -> Snapshot {
    Snapshot {
        schema_version: 1,
        environment: Default::default(),
        generated_at: String::new(),
        version: 1,
        flags,
        segments: vec![],
    }
}

#[test]
fn get_bool_details_returns_full_payload_on_hit() {
    let s = snap(vec![flag(
        "new-checkout",
        FlagType::Bool,
        VariationValue::Bool(true),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let details: FlagEvaluationDetails<bool> =
        client.get_bool_details("new-checkout".to_string(), false);
    assert!(details.value);
    assert_eq!(details.variant.as_deref(), Some("on"));
    assert_eq!(details.reason, Reason::Default);
    assert!(details.error_code.is_none());
    assert!(details.error_message.is_none());
    assert_eq!(details.flag_key, "new-checkout");
}

#[test]
fn get_bool_details_flag_not_found_surfaces_wire_code() {
    let s = snap(vec![]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let details = client.get_bool_details("missing".to_string(), true);
    assert!(details.value);
    assert_eq!(details.error_code.as_deref(), Some("FLAG_NOT_FOUND"));
    assert_eq!(details.reason, Reason::Error);
    assert!(details.variant.is_none());
}

#[test]
fn get_bool_details_type_mismatch_surfaces_wire_code() {
    let s = snap(vec![flag(
        "s",
        FlagType::String,
        VariationValue::String("x".to_string()),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let details = client.get_bool_details("s".to_string(), false);
    assert!(!details.value);
    assert_eq!(details.error_code.as_deref(), Some("TYPE_MISMATCH"));
}

#[test]
fn get_bool_details_provider_not_ready_when_no_snapshot() {
    let client = CoproductClient::empty_for_test();
    let details = client.get_bool_details("any".to_string(), true);
    assert!(details.value);
    assert_eq!(details.error_code.as_deref(), Some("PROVIDER_NOT_READY"));
}

#[test]
fn get_string_details_returns_typed_value() {
    let s = snap(vec![flag(
        "m",
        FlagType::String,
        VariationValue::String("Hi".to_string()),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let details = client.get_string_details("m".to_string(), "fb".to_string());
    assert_eq!(details.value, "Hi");
    assert!(details.error_code.is_none());
}

#[test]
fn get_int_details_truncates_and_carries_variant() {
    let s = snap(vec![flag(
        "n",
        FlagType::Number,
        VariationValue::Number(1.7),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let details = client.get_int_details("n".to_string(), 0);
    assert_eq!(details.value, 1);
    assert_eq!(details.variant.as_deref(), Some("on"));
}

#[test]
fn get_number_details_returns_typed_value() {
    let s = snap(vec![flag(
        "m",
        FlagType::Number,
        VariationValue::Number(2.5),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let details = client.get_number_details("m".to_string(), 0.0);
    assert_eq!(details.value, 2.5);
}

#[test]
fn get_json_details_returns_typed_value() {
    let payload = json!({ "k": "v" });
    let s = snap(vec![flag(
        "c",
        FlagType::Json,
        VariationValue::Json(payload.clone()),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let details = client.get_json_details("c".to_string(), json!({}));
    assert_eq!(details.value, payload);
}
