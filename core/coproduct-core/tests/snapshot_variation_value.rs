use coproduct_core::snapshot::{Variation, VariationValue};

#[test]
fn bool_variation_round_trips() {
    let wire = r#"{ "key": "on", "value": true }"#;
    let v: Variation = serde_json::from_str(wire).unwrap();
    assert_eq!(v.key, "on");
    assert_eq!(v.value, VariationValue::Bool(true));
    let back = serde_json::to_value(&v).unwrap();
    assert_eq!(back["value"], serde_json::json!(true));
}

#[test]
fn string_variation_round_trips() {
    let wire = r#"{ "key": "blue", "value": "navy" }"#;
    let v: Variation = serde_json::from_str(wire).unwrap();
    assert_eq!(v.value, VariationValue::String("navy".to_string()));
}

#[test]
fn number_variation_round_trips() {
    let wire = r#"{ "key": "price", "value": 9.99 }"#;
    let v: Variation = serde_json::from_str(wire).unwrap();
    match v.value {
        VariationValue::Number(n) => assert!((n - 9.99).abs() < 1e-9),
        other => panic!("expected Number, got {other:?}"),
    }
}

#[test]
fn json_variation_round_trips() {
    let wire = r#"{ "key": "cfg", "value": { "color": "red", "n": 3 } }"#;
    let v: Variation = serde_json::from_str(wire).unwrap();
    match &v.value {
        VariationValue::Json(j) => {
            assert_eq!(j["color"], "red");
            assert_eq!(j["n"], 3);
        }
        other => panic!("expected Json, got {other:?}"),
    }
}

#[test]
fn untagged_disambiguates_bool_from_number() {
    let b: VariationValue = serde_json::from_str("false").unwrap();
    assert_eq!(b, VariationValue::Bool(false));
    let n: VariationValue = serde_json::from_str("0").unwrap();
    assert_eq!(n, VariationValue::Number(0.0));
}
