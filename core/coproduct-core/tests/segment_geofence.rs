//! A geo-fence authored as a segment rule on `device_location`, resolving the
//! same way a country or city segment rule does. The fence rides the flat
//! `SegmentRule { attribute, operator, values }` shape via the `within_radius`
//! operator, so a segment needs no special-casing and the rule walker's
//! unknown-operator fail-closed covers an old SDK for free.

use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::operators::Operator;
use coproduct_core::snapshot::{
    Condition, ConditionOutcome, Segment, SegmentRule, evaluate_condition,
};
use std::collections::HashMap;

fn at(lat: f64, lng: f64) -> EvaluationContext {
    let mut map = HashMap::new();
    map.insert(
        "device_location".into(),
        AttributeValue::Array(vec![
            AttributeValue::Number(lat),
            AttributeValue::Number(lng),
        ]),
    );
    EvaluationContext::from_map(map)
}

fn sf_office_segment() -> Segment {
    Segment {
        key: "sf_office".into(),
        name: "SF office".into(),
        rules: vec![SegmentRule {
            attribute: "device_location".into(),
            operator: Operator::WithinRadius,
            values: vec!["37.7749".into(), "-122.4194".into(), "500".into()],
        }],
    }
}

fn segments() -> HashMap<String, Segment> {
    let mut m = HashMap::new();
    m.insert("sf_office".into(), sf_office_segment());
    m
}

fn sf_office_ref() -> Condition {
    Condition::Segment {
        segment_key: "sf_office".into(),
    }
}

#[test]
fn device_inside_the_segment_fence_matches() {
    assert_eq!(
        evaluate_condition(&sf_office_ref(), &at(37.7751, -122.4190), &segments()),
        ConditionOutcome::Match
    );
}

#[test]
fn device_outside_the_segment_fence_does_not_match() {
    assert_eq!(
        evaluate_condition(&sf_office_ref(), &at(37.8000, -122.4000), &segments()),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn missing_device_location_leaves_the_segment_indeterminate() {
    // No fix: the single geo rule is Indeterminate, so the segment (OR over its
    // rules) is Indeterminate, not a match and not a circuit-break
    let ctx = EvaluationContext::from_map(HashMap::new());
    assert_eq!(
        evaluate_condition(&sf_office_ref(), &ctx, &segments()),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn geo_rule_ors_with_other_rules_in_the_same_segment() {
    // A segment with a geo rule and a plain attribute rule matches a device that
    // satisfies either, confirming the fence is an ordinary OR member
    let mut segment = sf_office_segment();
    segment.rules.push(SegmentRule {
        attribute: "plan".into(),
        operator: Operator::Equals,
        values: vec!["premium".into()],
    });
    let mut segs = HashMap::new();
    segs.insert("sf_office".into(), segment);

    // Outside the fence but premium → matches on the second rule
    let mut map = HashMap::new();
    map.insert(
        "device_location".into(),
        AttributeValue::Array(vec![
            AttributeValue::Number(37.8000),
            AttributeValue::Number(-122.4000),
        ]),
    );
    map.insert("plan".into(), AttributeValue::String("premium".into()));
    let ctx = EvaluationContext::from_map(map);
    assert_eq!(
        evaluate_condition(&sf_office_ref(), &ctx, &segs),
        ConditionOutcome::Match
    );
}
