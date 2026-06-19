use coproduct_core::context::AttributeValue;
use coproduct_core::operators::{is_not_set, is_set};

#[test]
fn is_set_returns_false_for_missing() {
    assert!(!is_set(None));
    assert!(is_not_set(None));
}

#[test]
fn is_set_returns_false_for_explicit_null() {
    let v = AttributeValue::Null;
    assert!(!is_set(Some(&v)));
    assert!(is_not_set(Some(&v)));
}

#[test]
fn is_set_returns_true_for_empty_string() {
    let v = AttributeValue::String(String::new());
    assert!(is_set(Some(&v)), "empty string still counts as set");
    assert!(!is_not_set(Some(&v)));
}

#[test]
fn is_set_returns_true_for_whitespace_string() {
    let v = AttributeValue::String("  \t\n".to_string());
    assert!(is_set(Some(&v)));
}

#[test]
fn is_set_returns_true_for_zero_number() {
    let v = AttributeValue::Number(0.0);
    assert!(is_set(Some(&v)));
}

#[test]
fn is_set_returns_true_for_false_bool() {
    let v = AttributeValue::Bool(false);
    assert!(is_set(Some(&v)));
}

#[test]
fn is_set_returns_true_for_empty_array() {
    let v = AttributeValue::Array(vec![]);
    assert!(is_set(Some(&v)));
}

#[test]
fn is_set_returns_true_for_single_whitespace_element_array() {
    let v = AttributeValue::Array(vec![AttributeValue::String(" ".to_string())]);
    assert!(is_set(Some(&v)));
}
