use coproduct_core::snapshot::{Condition, Flag, FlagType, Operator, Rollout, Snapshot};

#[test]
fn flag_tolerates_unknown_top_level_field() {
    let wire = r#"{
        "key": "x",
        "type": "BOOL",
        "enabled": true,
        "isPaused": false,
        "variations": [],
        "offVariation": "off",
        "fallthroughVariation": "off",
        "targetingRules": [],
        "prerequisites": [],
        "experiment": null,
        "futureUnknownField": { "anything": [1, 2, 3] }
    }"#;
    let flag: Flag = serde_json::from_str(wire).unwrap();
    assert_eq!(flag.r#type, FlagType::Bool);
}

#[test]
fn snapshot_tolerates_unknown_top_level_field() {
    let wire = r#"{
        "schemaVersion": 1,
        "version": 1,
        "futureSection": "ignored"
    }"#;
    let snap: Snapshot = serde_json::from_str(wire).unwrap();
    assert_eq!(snap.schema_version, 1);
    assert_eq!(snap.version, 1);
}

#[test]
fn unknown_operator_does_not_abort_parse() {
    let wire = r#"{
        "type": "attribute",
        "attribute": "x",
        "operator": "starts_with_caseless",
        "values": []
    }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    match c {
        Condition::Attribute { operator, .. } => assert_eq!(operator, Operator::Unknown),
        other => panic!("expected Attribute with Unknown operator, got {other:?}"),
    }
}

#[test]
fn unknown_rollout_type_does_not_abort_parse() {
    let wire = r#"{ "type": "fancy_split", "rungs": [] }"#;
    let r: Rollout = serde_json::from_str(wire).unwrap();
    assert_eq!(r, Rollout::Unknown);
}

#[test]
fn unknown_condition_type_does_not_abort_parse() {
    let wire = r#"{ "type": "geofence", "polygons": [] }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    assert!(matches!(c, Condition::Unknown { .. }));
}

#[test]
fn missing_optional_arrays_default_to_empty() {
    let wire = r#"{
        "key": "x",
        "type": "BOOL",
        "offVariation": "off",
        "fallthroughVariation": "off"
    }"#;
    let flag: Flag = serde_json::from_str(wire).unwrap();
    assert!(flag.variations.is_empty());
    assert!(flag.targeting_rules.is_empty());
    assert!(flag.prerequisites.is_empty());
    assert!(flag.enabled, "enabled should default to true");
    assert!(!flag.is_paused, "isPaused should default to false");
}
