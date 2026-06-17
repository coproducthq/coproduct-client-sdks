use coproduct_core::snapshot::Coverage;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Envelope {
    #[serde(
        default,
        deserialize_with = "coproduct_core::snapshot::deserialize_coverage"
    )]
    coverage: Coverage,
}

fn parse(j: &str) -> Coverage {
    let env: Envelope = serde_json::from_str(j).expect("envelope should parse");
    env.coverage
}

#[test]
fn absent_coverage_becomes_10000() {
    assert_eq!(parse("{}"), Coverage(10000));
}

#[test]
fn null_coverage_becomes_0() {
    assert_eq!(parse(r#"{ "coverage": null }"#), Coverage(0));
}

#[test]
fn in_range_integer_passes_through() {
    assert_eq!(parse(r#"{ "coverage": 5000 }"#), Coverage(5000));
    assert_eq!(parse(r#"{ "coverage": 0 }"#), Coverage(0));
    assert_eq!(parse(r#"{ "coverage": 10000 }"#), Coverage(10000));
}

#[test]
fn finite_float_truncates_toward_zero() {
    assert_eq!(parse(r#"{ "coverage": 2500.9 }"#), Coverage(2500));
    assert_eq!(parse(r#"{ "coverage": 2500.001 }"#), Coverage(2500));
}

#[test]
fn over_range_clamps_to_10000() {
    assert_eq!(parse(r#"{ "coverage": 15000 }"#), Coverage(10000));
    assert_eq!(parse(r#"{ "coverage": 99999999 }"#), Coverage(10000));
}

#[test]
fn negative_clamps_to_0() {
    assert_eq!(parse(r#"{ "coverage": -5 }"#), Coverage(0));
    assert_eq!(parse(r#"{ "coverage": -10000 }"#), Coverage(0));
}

#[test]
fn non_numeric_string_becomes_0() {
    assert_eq!(parse(r#"{ "coverage": "5000" }"#), Coverage(0));
    assert_eq!(parse(r#"{ "coverage": "abc" }"#), Coverage(0));
}

#[test]
fn bool_becomes_0() {
    assert_eq!(parse(r#"{ "coverage": true }"#), Coverage(0));
    assert_eq!(parse(r#"{ "coverage": false }"#), Coverage(0));
}

#[test]
fn object_becomes_0() {
    assert_eq!(parse(r#"{ "coverage": {} }"#), Coverage(0));
    assert_eq!(parse(r#"{ "coverage": {"x":1} }"#), Coverage(0));
}

#[test]
fn array_becomes_0() {
    assert_eq!(parse(r#"{ "coverage": [] }"#), Coverage(0));
    assert_eq!(parse(r#"{ "coverage": [5000] }"#), Coverage(0));
}

#[test]
fn nan_becomes_0() {
    use coproduct_core::snapshot::coalesce_coverage_value;
    let nan = serde_json::Number::from_f64(f64::NAN);
    assert!(nan.is_none(), "serde_json correctly refuses NaN");
    let inf = serde_json::Number::from_f64(f64::INFINITY);
    assert!(inf.is_none(), "serde_json correctly refuses Infinity");
    assert_eq!(
        coalesce_coverage_value(serde_json::Value::Null),
        Coverage(0)
    );
}
