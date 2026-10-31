//! Geo-fence targeting: haversine distance math, the `geofence` condition node's
//! tolerant decode, and its inside/outside/absent evaluation outcomes.

use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::geo::haversine_meters;
use coproduct_core::snapshot::{Condition, ConditionOutcome, Segment, evaluate_condition};
use std::collections::HashMap;

/// One degree of longitude at the equator, from the mean-Earth-radius haversine.
const EQUATOR_DEGREE_METERS: f64 = 111_194.9;

fn point(lat: f64, lng: f64) -> AttributeValue {
    AttributeValue::Array(vec![
        AttributeValue::Number(lat),
        AttributeValue::Number(lng),
    ])
}

fn ctx_with_location(value: Option<AttributeValue>) -> EvaluationContext {
    let mut map = HashMap::new();
    if let Some(v) = value {
        map.insert("device_location".to_string(), v);
    }
    EvaluationContext::from_map(map)
}

fn sf_fence(radius_m: f64) -> Condition {
    Condition::Geofence {
        attribute: "device_location".to_string(),
        center_lat: 37.7749,
        center_lng: -122.4194,
        radius_m,
    }
}

fn no_segments() -> HashMap<String, Segment> {
    HashMap::new()
}

#[test]
fn haversine_zero_distance_is_zero() {
    assert_eq!(
        haversine_meters(37.7749, -122.4194, 37.7749, -122.4194),
        0.0
    );
}

#[test]
fn haversine_one_equatorial_degree_longitude() {
    let d = haversine_meters(0.0, 0.0, 0.0, 1.0);
    assert!((d - EQUATOR_DEGREE_METERS).abs() < 2.0, "got {d} m");
}

#[test]
fn haversine_one_degree_latitude() {
    let d = haversine_meters(0.0, 0.0, 1.0, 0.0);
    assert!((d - EQUATOR_DEGREE_METERS).abs() < 2.0, "got {d} m");
}

#[test]
fn geofence_node_decodes_from_wire() {
    let wire = r#"{
        "type": "geofence",
        "attribute": "device_location",
        "center": { "lat": 37.7749, "lng": -122.4194 },
        "radius_m": 500
    }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    match c {
        Condition::Geofence {
            attribute,
            center_lat,
            center_lng,
            radius_m,
        } => {
            assert_eq!(attribute, "device_location");
            assert_eq!(center_lat, 37.7749);
            assert_eq!(center_lng, -122.4194);
            assert_eq!(radius_m, 500.0);
        }
        other => panic!("expected Geofence, got {other:?}"),
    }
}

#[test]
fn geofence_round_trips_through_serialization() {
    let original = sf_fence(500.0);
    let json = serde_json::to_string(&original).unwrap();
    let back: Condition = serde_json::from_str(&json).unwrap();
    assert_eq!(original, back);
}

#[test]
fn geofence_polygon_body_decodes_to_unknown() {
    // Circle-only in v1: a future polygon body has no center/radius and must stay
    // a forward-incompatible node that fails closed, not a half-parsed circle.
    let wire = r#"{ "type": "geofence", "polygons": [] }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    assert!(matches!(c, Condition::Unknown { .. }));
}

#[test]
fn geofence_matches_a_device_inside_the_circle() {
    // ~333 m due north of the center, well inside 500 m.
    let ctx = ctx_with_location(Some(point(37.7779, -122.4194)));
    assert_eq!(
        evaluate_condition(&sf_fence(500.0), &ctx, &no_segments()),
        ConditionOutcome::Match
    );
}

#[test]
fn geofence_does_not_match_a_device_outside_the_circle() {
    // ~800 m due north of the center, outside 500 m.
    let ctx = ctx_with_location(Some(point(37.7821, -122.4194)));
    assert_eq!(
        evaluate_condition(&sf_fence(500.0), &ctx, &no_segments()),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn geofence_is_indeterminate_when_location_absent() {
    let ctx = ctx_with_location(None);
    assert_eq!(
        evaluate_condition(&sf_fence(500.0), &ctx, &no_segments()),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn geofence_is_indeterminate_when_location_malformed() {
    // A string where a [lat, lng] number array is expected cannot be matched; it
    // reads as no location rather than a false negative.
    let ctx = ctx_with_location(Some(AttributeValue::String("37.7,-122.4".into())));
    assert_eq!(
        evaluate_condition(&sf_fence(500.0), &ctx, &no_segments()),
        ConditionOutcome::Indeterminate
    );
}
