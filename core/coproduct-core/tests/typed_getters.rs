use coproduct_core::client::CoproductClient;
use coproduct_core::snapshot::{Flag, FlagType, Snapshot, Variation, VariationValue};
use serde_json::json;

fn flag(key: &str, flag_type: FlagType, value: VariationValue) -> Flag {
    Flag {
        key: key.to_string(),
        r#type: flag_type,
        enabled: true,
        is_paused: false,
        variations: vec![Variation {
            key: "v".to_string(),
            value,
            name: None,
        }],
        off_variation: Some("v".to_string()),
        fallthrough_variation: Some("v".to_string()),
        targeting_rules: vec![],
        prerequisites: vec![],
        experiment: None,
    }
}

fn snapshot(flags: Vec<Flag>) -> Snapshot {
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
fn get_string_returns_typed_value() {
    let s = snapshot(vec![flag(
        "msg",
        FlagType::String,
        VariationValue::String("Hi".to_string()),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(
        client.get_string("msg".to_string(), "fallback".to_string()),
        "Hi"
    );
}

#[test]
fn get_string_returns_default_on_type_mismatch() {
    let s = snapshot(vec![flag("b", FlagType::Bool, VariationValue::Bool(true))]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(client.get_string("b".to_string(), "fb".to_string()), "fb");
}

#[test]
fn get_number_returns_typed_value() {
    let s = snapshot(vec![flag(
        "mult",
        FlagType::Number,
        VariationValue::Number(1.5),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(client.get_number("mult".to_string(), 1.0), 1.5);
}

#[test]
fn get_int_truncates_toward_zero_positive() {
    let s = snapshot(vec![flag(
        "n",
        FlagType::Number,
        VariationValue::Number(1.7),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(client.get_int("n".to_string(), 0), 1);
}

#[test]
fn get_int_truncates_toward_zero_negative() {
    let s = snapshot(vec![flag(
        "n",
        FlagType::Number,
        VariationValue::Number(-1.7),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(client.get_int("n".to_string(), 0), -1);
}

#[test]
fn get_int_returns_default_on_nan_or_infinite() {
    let s_nan = snapshot(vec![flag(
        "n",
        FlagType::Number,
        VariationValue::Number(f64::NAN),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s_nan);
    assert_eq!(client.get_int("n".to_string(), 42), 42);

    let s_inf = snapshot(vec![flag(
        "n",
        FlagType::Number,
        VariationValue::Number(f64::INFINITY),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s_inf);
    assert_eq!(client.get_int("n".to_string(), 99), 99);
}

#[test]
fn get_int_clamps_out_of_range_to_default() {
    let s = snapshot(vec![flag(
        "n",
        FlagType::Number,
        VariationValue::Number(1e30),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(client.get_int("n".to_string(), 7), 7);
}

#[test]
fn get_json_returns_value() {
    let payload = json!({ "color": "red", "size": 12 });
    let s = snapshot(vec![flag(
        "cfg",
        FlagType::Json,
        VariationValue::Json(payload.clone()),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(client.get_json("cfg".to_string(), json!({})), payload);
}

#[test]
fn get_json_returns_default_on_type_mismatch() {
    let s = snapshot(vec![flag("b", FlagType::Bool, VariationValue::Bool(false))]);
    let client = CoproductClient::with_snapshot_for_test(s);
    let default = json!({ "fallback": true });
    assert_eq!(client.get_json("b".to_string(), default.clone()), default);
}
