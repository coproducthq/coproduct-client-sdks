//! Geo-fence targeting: the `within_radius` operator over a `[lat, lng]` device
//! point and a `[center_lat, center_lng, radius_m]` fence, asserting the
//! inside/outside boundary and the fail-safe (absent or malformed data is
//! Indeterminate, never a circuit-break).

use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::operators::Operator;
use coproduct_core::snapshot::{Condition, ConditionOutcome, Segment, evaluate_condition};
use std::collections::HashMap;

// SF ferry building area, used as the fence center throughout
const CENTER_LAT: &str = "37.7749";
const CENTER_LNG: &str = "-122.4194";

/// A geo-fence condition over `device_location` with the given radius in meters
fn fence(radius_m: &str) -> Condition {
    Condition::Attribute {
        attribute: "device_location".into(),
        operator: Operator::WithinRadius,
        values: vec![CENTER_LAT.into(), CENTER_LNG.into(), radius_m.into()],
    }
}

/// A context whose `device_location` is the given point
fn at(lat: f64, lng: f64) -> EvaluationContext {
    with_location(AttributeValue::Array(vec![
        AttributeValue::Number(lat),
        AttributeValue::Number(lng),
    ]))
}

/// A context with a `device_location` value of the given shape
fn with_location(value: AttributeValue) -> EvaluationContext {
    let mut map = HashMap::new();
    map.insert("device_location".into(), value);
    EvaluationContext::from_map(map)
}

fn no_segments() -> HashMap<String, Segment> {
    HashMap::new()
}

#[test]
fn device_inside_the_fence_matches() {
    // ~44 m from center, well inside a 500 m fence
    let ctx = at(37.7751, -122.4190);
    assert_eq!(
        evaluate_condition(&fence("500"), &ctx, &no_segments()),
        ConditionOutcome::Match
    );
}

#[test]
fn device_outside_the_fence_does_not_match() {
    // ~44 m from center is outside a 10 m fence
    let ctx = at(37.7751, -122.4190);
    assert_eq!(
        evaluate_condition(&fence("10"), &ctx, &no_segments()),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn zero_radius_matches_only_the_exact_center() {
    let at_center = at(37.7749, -122.4194);
    assert_eq!(
        evaluate_condition(&fence("0"), &at_center, &no_segments()),
        ConditionOutcome::Match
    );
    let one_step_off = at(37.7750, -122.4194);
    assert_eq!(
        evaluate_condition(&fence("0"), &one_step_off, &no_segments()),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn absent_device_location_is_indeterminate_not_circuit_break() {
    // No fix: fall through to Indeterminate (→ flag default), never a circuit-break
    let ctx = EvaluationContext::from_map(HashMap::new());
    assert_eq!(
        evaluate_condition(&fence("500"), &ctx, &no_segments()),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn malformed_device_location_shapes_are_indeterminate() {
    // Every shape that is not a two-element finite-number array fails safe
    for bad in [
        AttributeValue::String("37.7749,-122.4194".into()),
        AttributeValue::Number(37.7749),
        AttributeValue::Array(vec![AttributeValue::Number(37.7749)]),
        AttributeValue::Array(vec![
            AttributeValue::Number(37.7749),
            AttributeValue::Number(-122.4194),
            AttributeValue::Number(0.0),
        ]),
        AttributeValue::Array(vec![
            AttributeValue::Number(f64::NAN),
            AttributeValue::Number(-122.4194),
        ]),
        AttributeValue::Array(vec![
            AttributeValue::String("37.7749".into()),
            AttributeValue::String("-122.4194".into()),
        ]),
    ] {
        assert_eq!(
            evaluate_condition(&fence("500"), &with_location(bad.clone()), &no_segments()),
            ConditionOutcome::Indeterminate,
            "malformed device_location {bad:?} should be Indeterminate",
        );
    }
}

#[test]
fn malformed_fence_values_are_indeterminate() {
    let ctx = at(37.7749, -122.4194);
    let cases = [
        // too few values
        vec![CENTER_LAT.to_string(), CENTER_LNG.to_string()],
        // non-numeric radius
        vec![
            CENTER_LAT.to_string(),
            CENTER_LNG.to_string(),
            "far".to_string(),
        ],
        // negative radius
        vec![
            CENTER_LAT.to_string(),
            CENTER_LNG.to_string(),
            "-100".to_string(),
        ],
        // empty
        vec![],
    ];
    for values in cases {
        let cond = Condition::Attribute {
            attribute: "device_location".into(),
            operator: Operator::WithinRadius,
            values: values.clone(),
        };
        assert_eq!(
            evaluate_condition(&cond, &ctx, &no_segments()),
            ConditionOutcome::Indeterminate,
            "malformed fence {values:?} should be Indeterminate",
        );
    }
}

#[test]
fn negated_geo_fence_preserves_indeterminate_for_missing_location() {
    // Conservative negation: no location stays Indeterminate, not a Not-match
    let ctx = EvaluationContext::from_map(HashMap::new());
    let cond = Condition::Not {
        rule: Box::new(fence("500")),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &no_segments()),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn within_radius_operator_parses_from_its_wire_name() {
    let parsed: Operator = serde_json::from_str("\"within_radius\"").unwrap();
    assert_eq!(parsed, Operator::WithinRadius);
}
