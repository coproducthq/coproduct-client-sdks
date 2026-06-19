use coproduct_core::client::CoproductClient;
use coproduct_core::snapshot::{Flag, FlagType, Snapshot, Variation, VariationValue};

fn number_flag(key: &str, n: f64) -> Snapshot {
    Snapshot {
        schema_version: 1,
        environment: Default::default(),
        generated_at: String::new(),
        version: 1,
        flags: vec![Flag {
            key: key.to_string(),
            r#type: FlagType::Number,
            enabled: true,
            is_paused: false,
            variations: vec![Variation {
                key: "v".to_string(),
                value: VariationValue::Number(n),
                name: None,
            }],
            off_variation: Some("v".to_string()),
            fallthrough_variation: Some("v".to_string()),
            targeting_rules: vec![],
            prerequisites: vec![],
            experiment: None,
        }],
        segments: vec![],
    }
}

#[test]
fn get_int_truncates_one_point_seven_to_one() {
    let client = CoproductClient::with_snapshot_for_test(number_flag("page-size", 1.7));
    assert_eq!(client.get_int("page-size".to_string(), 0), 1);
}

#[test]
fn get_int_truncates_negative_one_point_seven_to_negative_one() {
    let client = CoproductClient::with_snapshot_for_test(number_flag("offset", -1.7));
    assert_eq!(client.get_int("offset".to_string(), 0), -1);
}

#[test]
fn get_int_truncates_zero_point_nine_to_zero() {
    let client = CoproductClient::with_snapshot_for_test(number_flag("k", 0.9));
    assert_eq!(client.get_int("k".to_string(), 99), 0);
}

#[test]
fn get_int_truncates_negative_zero_point_nine_to_zero() {
    let client = CoproductClient::with_snapshot_for_test(number_flag("k", -0.9));
    assert_eq!(client.get_int("k".to_string(), 99), 0);
}

#[test]
fn get_int_returns_exact_value_for_integer_doubles() {
    let client = CoproductClient::with_snapshot_for_test(number_flag("k", 42.0));
    assert_eq!(client.get_int("k".to_string(), 0), 42);
}

#[test]
fn get_int_details_carries_the_truncated_value() {
    let client = CoproductClient::with_snapshot_for_test(number_flag("k", 1.7));
    let details = client.get_int_details("k".to_string(), 0);
    assert_eq!(details.value, 1);
    assert!(
        details.error_code.is_none(),
        "truncation is not an error path"
    );
}
