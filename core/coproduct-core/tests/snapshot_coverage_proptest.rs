//! Property tests for the coverage coalesce. The spec lists exactly
//! three branches:
//!   - absent (10000), handled by `#[serde(default)]` at the struct
//!     boundary; not exercised here because `coalesce_coverage_value`
//!     takes a `Value` directly and never sees absence
//!   - present finite (truncate + clamp)
//!   - present non-finite (0)
//!
//! Each present-value branch becomes a proptest invariant

use coproduct_core::snapshot::{Coverage, coalesce_coverage_value};
use proptest::prelude::*;
use serde_json::Value;

proptest! {
 /// Present-null fails closed at 0. This is the regression fix that keeps it
 /// distinct from absent, which is 10000 via the struct field default
    #[test]
    fn null_fails_closed_to_zero(_seed in any::<u64>()) {
        prop_assert_eq!(coalesce_coverage_value(Value::Null), Coverage(0));
    }

 /// Branch 2a: present finite integer in [0, 10000] passes through
    #[test]
    fn in_range_integer_passes_through(n in 0u32..=10000u32) {
        let v = Value::Number(n.into());
        prop_assert_eq!(coalesce_coverage_value(v), Coverage(n));
    }

 /// Branch 2b: present finite integer above 10000 clamps to 10000
    #[test]
    fn over_range_integer_clamps_to_ceiling(n in 10001u64..=u64::MAX) {
        let v = Value::Number(n.into());
        prop_assert_eq!(coalesce_coverage_value(v), Coverage(10000));
    }

 /// Branch 2c: present negative integer clamps to 0
    #[test]
    fn negative_integer_clamps_to_floor(n in i64::MIN..=-1_i64) {
        let v = Value::Number(n.into());
        prop_assert_eq!(coalesce_coverage_value(v), Coverage(0));
    }

 /// Branch 2d: present finite float in (0, 10000) truncates toward zero
 /// and the result equals floor(f) when f > 0
    #[test]
    fn finite_float_truncates_toward_zero(f in 0.0f64..10000.0f64) {
        let n = serde_json::Number::from_f64(f).unwrap();
        let v = Value::Number(n);
        prop_assert_eq!(
            coalesce_coverage_value(v),
            Coverage(f.trunc() as u32)
        );
    }

 /// Branch 2e: present finite float above 10000 clamps
    #[test]
    fn over_range_float_clamps_to_ceiling(f in 10000.0f64..1e12_f64) {
        let n = serde_json::Number::from_f64(f).unwrap();
        let v = Value::Number(n);
        prop_assert_eq!(coalesce_coverage_value(v), Coverage(10000));
    }

 /// Branch 2f: present negative float clamps to 0
    #[test]
    fn negative_float_clamps_to_floor(f in -1e12_f64..-0.001_f64) {
        let n = serde_json::Number::from_f64(f).unwrap();
        let v = Value::Number(n);
        prop_assert_eq!(coalesce_coverage_value(v), Coverage(0));
    }

 /// Branch 3a: present string is non-numeric for this coalesce, ALWAYS 0.
 /// (The spec is explicit: even a numeric string like "5000" fails closed)
    #[test]
    fn string_value_fails_closed_to_zero(s in "[a-zA-Z0-9]{0,32}") {
        let v = Value::String(s);
        prop_assert_eq!(coalesce_coverage_value(v), Coverage(0));
    }

 /// Branch 3b: present bool is non-numeric, ALWAYS 0
    #[test]
    fn bool_value_fails_closed_to_zero(b in any::<bool>()) {
        let v = Value::Bool(b);
        prop_assert_eq!(coalesce_coverage_value(v), Coverage(0));
    }
}

// Branch 3c: present null is special-cased to 0 (NOT 10000). Exercised
// here as a single concrete case because proptest can't generate Null
// in a non-trivial way
#[test]
fn null_value_fails_closed_to_zero_not_full() {
    assert_eq!(coalesce_coverage_value(Value::Null), Coverage(0));
}

// The fail-open regression test: absent and null MUST diverge. Exercised
// at the STRUCT boundary because absent is handled by `#[serde(default)]`
// before the coalesce function runs. The earlier signature
// (`coalesce_coverage_value(Option<Value>)`) collapsed present-null to
// `None` and turned this bug into a silent fail-open, which is why the
// function now takes a `Value` directly
#[test]
fn absent_and_null_must_diverge_at_struct_boundary() {
    use serde::Deserialize;

    #[derive(Debug, Deserialize)]
    struct E {
        #[serde(
            default,
            deserialize_with = "coproduct_core::snapshot::deserialize_coverage"
        )]
        coverage: Coverage,
    }

    let absent: E = serde_json::from_str("{}").unwrap();
    let null: E = serde_json::from_str(r#"{ "coverage": null }"#).unwrap();
    assert_eq!(
        absent.coverage,
        Coverage(10000),
        "absent must be full inclusion"
    );
    assert_eq!(null.coverage, Coverage(0), "null must be fail-closed");
    assert_ne!(
        absent.coverage, null.coverage,
        "absent and null must NOT collapse together"
    );
}

// Branch 3d: present array / object fails closed to 0
#[test]
fn array_and_object_fail_closed_to_zero() {
    assert_eq!(
        coalesce_coverage_value(serde_json::json!([1, 2, 3])),
        Coverage(0)
    );
    assert_eq!(
        coalesce_coverage_value(serde_json::json!({ "n": 5000 })),
        Coverage(0)
    );
}
