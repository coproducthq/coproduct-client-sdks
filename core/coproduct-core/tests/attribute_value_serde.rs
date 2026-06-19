use coproduct_core::context::AttributeValue;
use serde_json::json;

#[test]
fn parses_bool_string_number_null() {
    let b: AttributeValue = serde_json::from_value(json!(true)).unwrap();
    assert_eq!(b, AttributeValue::Bool(true));

    let s: AttributeValue = serde_json::from_value(json!("alpha")).unwrap();
    assert_eq!(s, AttributeValue::String("alpha".to_string()));

    let n: AttributeValue = serde_json::from_value(json!(42.5)).unwrap();
    assert_eq!(n, AttributeValue::Number(42.5));

    let nu: AttributeValue = serde_json::from_value(json!(null)).unwrap();
    assert_eq!(nu, AttributeValue::Null);
}

#[test]
fn parses_integer_as_number() {
    let n: AttributeValue = serde_json::from_value(json!(42)).unwrap();
    assert_eq!(n, AttributeValue::Number(42.0));
}

#[test]
fn parses_array_of_strings() {
    let v: AttributeValue = serde_json::from_value(json!(["us", "ca", "uk"])).unwrap();
    let AttributeValue::Array(items) = v else {
        panic!("expected Array");
    };
    assert_eq!(items.len(), 3);
    assert_eq!(items[0], AttributeValue::String("us".to_string()));
}

#[test]
fn round_trips_through_json() {
    let original = AttributeValue::Array(vec![
        AttributeValue::String("us".to_string()),
        AttributeValue::Number(7.0),
        AttributeValue::Bool(false),
    ]);
    let s = serde_json::to_string(&original).unwrap();
    let parsed: AttributeValue = serde_json::from_str(&s).unwrap();
    assert_eq!(parsed, original);
}
