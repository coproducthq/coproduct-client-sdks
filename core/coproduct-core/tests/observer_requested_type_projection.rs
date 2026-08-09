use coproduct_core::eval::number_to_int;
use coproduct_core::observer::FlagValue;

#[test]
fn an_integer_projection_truncates_toward_zero() {
    assert_eq!(FlagValue::Number(3.7).as_int(), Some(3));
    assert_eq!(FlagValue::Number(-3.7).as_int(), Some(-3));
    assert_eq!(FlagValue::Number(0.0).as_int(), Some(0));
}

#[test]
fn an_unrepresentable_number_has_no_integer_projection() {
    // A number observation still delivers these, while an integer observation
    // resolves to the caller's integer default
    assert_eq!(FlagValue::Number(1e100).as_int(), None);
    assert_eq!(FlagValue::Number(f64::NAN).as_int(), None);
    assert_eq!(FlagValue::Number(f64::INFINITY).as_int(), None);
    assert_eq!(FlagValue::Number(1e100).as_number(), Some(1e100));
}

#[test]
fn the_integer_projector_is_the_one_the_getters_use() {
    // The shared projector is the getters' rule, so an observation and get_int
    // cannot drift
    assert_eq!(number_to_int(9.99), Some(9));
    assert_eq!(number_to_int(i64::MAX as f64 * 2.0), None);
}

#[test]
fn the_integer_bounds_reject_the_unrepresentable_edge() {
    // i64::MAX is not representable as an f64 and rounds up to 2^63, so a bound
    // written as `> i64::MAX as f64` would admit exactly 2^63 and the cast would
    // saturate it to i64::MAX. It must be unavailable instead
    let two_pow_63 = 9_223_372_036_854_775_808.0_f64;
    assert_eq!(
        i64::MAX as f64,
        two_pow_63,
        "the rounding this bound guards"
    );
    assert_eq!(number_to_int(two_pow_63), None);
    assert_eq!(number_to_int(-two_pow_63), Some(i64::MIN), "-2^63 is exact");
    // The largest and smallest f64 values that are strictly inside the range
    let below = f64::from_bits(two_pow_63.to_bits() - 1);
    assert_eq!(number_to_int(below), Some(below as i64));
    assert_eq!(
        number_to_int(two_pow_63 - 1024.0),
        Some(9_223_372_036_854_774_784)
    );
}

#[test]
fn a_variant_mismatch_has_no_projection() {
    assert_eq!(FlagValue::String("x".to_string()).as_bool(), None);
    assert_eq!(FlagValue::Bool(true).as_number(), None);
    assert_eq!(FlagValue::Bool(true).as_json_string(), None);
    assert_eq!(
        FlagValue::Json(serde_json::json!({"a": 1})).as_json_string(),
        Some("{\"a\":1}".to_string())
    );
}
