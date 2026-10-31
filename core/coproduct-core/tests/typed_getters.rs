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
        onboarding_flows: vec![],
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

#[test]
fn get_string_list_returns_typed_value() {
    let s = snapshot(vec![flag(
        "emails",
        FlagType::StringList,
        VariationValue::StringList(vec!["a@x.com".to_string()]),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(
        client.get_string_list("emails".to_string(), vec!["fallback".to_string()]),
        vec!["a@x.com".to_string()]
    );
}

#[test]
fn get_number_list_returns_typed_value() {
    let s = snapshot(vec![flag(
        "weights",
        FlagType::NumberList,
        VariationValue::NumberList(vec![1.5, 2.5]),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(
        client.get_number_list("weights".to_string(), vec![0.0]),
        vec![1.5, 2.5]
    );
}

#[test]
fn get_string_list_returns_default_on_type_mismatch() {
    let s = snapshot(vec![flag(
        "n",
        FlagType::Number,
        VariationValue::Number(1.0),
    )]);
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(
        client.get_string_list("n".to_string(), vec!["fallback".to_string()]),
        vec!["fallback".to_string()]
    );
}

// A NUMBER_LIST flag whose variation value is the wire JSON array `[]`.
// Deserializing it exercises the untagged VariationValue matcher directly: an
// empty array binds to StringList(vec![]) because StringList precedes
// NumberList in declaration order. The empty-aware as_number_list projection
// must still treat that as a valid empty number list rather than falling back
// to the caller default
#[test]
fn get_number_list_returns_empty_list_for_empty_number_list_flag_from_wire_json() {
    let wire = r#"{
        "schemaVersion": 1,
        "version": 1,
        "flags": [
            {
                "key": "scores",
                "type": "NUMBER_LIST",
                "enabled": true,
                "isPaused": false,
                "variations": [{ "key": "on", "value": [] }],
                "offVariation": "on",
                "fallthroughVariation": "on",
                "prerequisites": [],
                "targetingRules": []
            }
        ],
        "segments": []
    }"#;
    let s: Snapshot = serde_json::from_str(wire).expect("wire snapshot deserializes");
    let client = CoproductClient::with_snapshot_for_test(s);
    assert_eq!(
        client.get_number_list("scores".to_string(), vec![99.0]),
        Vec::<f64>::new()
    );
}
