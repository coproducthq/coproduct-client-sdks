use coproduct_core::client::CoproductClient;
use coproduct_core::snapshot::{Flag, FlagType, Snapshot, Variation, VariationValue};

fn snapshot_with_bool_flag(key: &str, value: bool) -> Snapshot {
    Snapshot {
        schema_version: 1,
        environment: Default::default(),
        generated_at: String::new(),
        version: 1,
        flags: vec![Flag {
            key: key.to_string(),
            r#type: FlagType::Bool,
            enabled: true,
            is_paused: false,
            variations: vec![Variation {
                key: "on".to_string(),
                value: VariationValue::Bool(value),
                name: None,
            }],
            off_variation: Some("on".to_string()),
            fallthrough_variation: Some("on".to_string()),
            targeting_rules: vec![],
            prerequisites: vec![],
            experiment: None,
        }],
        segments: vec![],
    }
}

#[test]
fn get_bool_returns_typed_value_from_snapshot() {
    let client =
        CoproductClient::with_snapshot_for_test(snapshot_with_bool_flag("new-checkout", true));
    assert!(client.get_bool("new-checkout".to_string(), false));
}

#[test]
fn get_bool_returns_default_when_flag_missing() {
    let client = CoproductClient::with_snapshot_for_test(snapshot_with_bool_flag("other", true));
    assert!(!client.get_bool("missing".to_string(), false));
    assert!(client.get_bool("missing".to_string(), true));
}

#[test]
fn get_bool_returns_default_when_no_snapshot() {
    let client = CoproductClient::empty_for_test();
    assert!(client.get_bool("any".to_string(), true));
    assert!(!client.get_bool("any".to_string(), false));
}

#[test]
fn get_bool_returns_default_on_type_mismatch() {
    let mut snap = snapshot_with_bool_flag("str-flag", true);
    snap.flags[0].r#type = FlagType::String;
    snap.flags[0].variations[0].value = VariationValue::String("hello".to_string());
    let client = CoproductClient::with_snapshot_for_test(snap);
    assert!(!client.get_bool("str-flag".to_string(), false));
}
