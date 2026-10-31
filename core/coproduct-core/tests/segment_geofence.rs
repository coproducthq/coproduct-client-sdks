//! A geo-fence authored as a segment rule on `device_location`, resolving the
//! same way a country or city segment rule does: the device attribute is matched
//! against the rule, and the segment resolves Match/NoMatch/Indeterminate.

use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::snapshot::{
    Condition, ConditionOutcome, Segment, SegmentRule, evaluate_condition,
};
use std::collections::HashMap;

fn point(lat: f64, lng: f64) -> AttributeValue {
    AttributeValue::Array(vec![
        AttributeValue::Number(lat),
        AttributeValue::Number(lng),
    ])
}

fn sf_office_segment() -> Segment {
    Segment {
        key: "sf_office".into(),
        name: "SF office".into(),
        rules: vec![SegmentRule::Geofence {
            attribute: "device_location".into(),
            center_lat: 37.7749,
            center_lng: -122.4194,
            radius_m: 500.0,
        }],
    }
}

fn ctx_with_location(value: Option<AttributeValue>) -> EvaluationContext {
    let mut map = HashMap::new();
    if let Some(v) = value {
        map.insert("device_location".to_string(), v);
    }
    EvaluationContext::from_map(map)
}

fn segments() -> HashMap<String, Segment> {
    let mut m = HashMap::new();
    m.insert("sf_office".into(), sf_office_segment());
    m
}

fn ref_sf_office() -> Condition {
    Condition::Segment {
        segment_key: "sf_office".into(),
    }
}

#[test]
fn segment_geofence_rule_decodes_from_wire() {
    let wire = r#"{
        "type": "geofence",
        "attribute": "device_location",
        "center": { "lat": 37.7749, "lng": -122.4194 },
        "radius_m": 500
    }"#;
    let rule: SegmentRule = serde_json::from_str(wire).unwrap();
    assert_eq!(
        rule,
        SegmentRule::Geofence {
            attribute: "device_location".into(),
            center_lat: 37.7749,
            center_lng: -122.4194,
            radius_m: 500.0,
        }
    );
}

#[test]
fn legacy_attribute_rule_still_decodes_without_a_type_field() {
    let wire = r#"{ "attribute": "country", "operator": "equals", "values": ["US"] }"#;
    let rule: SegmentRule = serde_json::from_str(wire).unwrap();
    assert!(matches!(rule, SegmentRule::Attribute { .. }));
}

#[test]
fn segment_matches_device_inside_the_geofence() {
    // ~333 m north of center, inside 500 m.
    let ctx = ctx_with_location(Some(point(37.7779, -122.4194)));
    assert_eq!(
        evaluate_condition(&ref_sf_office(), &ctx, &segments()),
        ConditionOutcome::Match
    );
}

#[test]
fn segment_no_match_for_device_outside_the_geofence() {
    // ~800 m north of center, outside 500 m.
    let ctx = ctx_with_location(Some(point(37.7821, -122.4194)));
    assert_eq!(
        evaluate_condition(&ref_sf_office(), &ctx, &segments()),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn segment_indeterminate_when_location_absent() {
    let ctx = ctx_with_location(None);
    assert_eq!(
        evaluate_condition(&ref_sf_office(), &ctx, &segments()),
        ConditionOutcome::Indeterminate
    );
}
