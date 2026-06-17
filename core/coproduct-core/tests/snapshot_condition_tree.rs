use coproduct_core::snapshot::{Condition, Operator};

#[test]
fn attribute_condition_round_trips() {
    let wire = r#"{
        "type": "attribute",
        "attribute": "country",
        "operator": "equals",
        "values": ["US", "CA"]
    }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    match &c {
        Condition::Attribute {
            attribute,
            operator,
            values,
        } => {
            assert_eq!(attribute, "country");
            assert_eq!(*operator, Operator::Equals);
            assert_eq!(values, &vec!["US".to_string(), "CA".to_string()]);
        }
        other => panic!("expected Attribute, got {other:?}"),
    }
}

#[test]
fn segment_condition_round_trips() {
    let wire = r#"{ "type": "segment", "segment_key": "internal_users" }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    assert_eq!(
        c,
        Condition::Segment {
            segment_key: "internal_users".to_string()
        }
    );
}

#[test]
fn always_condition_round_trips() {
    let c: Condition = serde_json::from_str(r#"{ "type": "always" }"#).unwrap();
    assert_eq!(c, Condition::Always);
}

#[test]
fn and_condition_nests() {
    let wire = r#"{
        "type": "and",
        "rules": [
            { "type": "always" },
            { "type": "segment", "segment_key": "x" }
        ]
    }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    match c {
        Condition::And { rules } => assert_eq!(rules.len(), 2),
        other => panic!("expected And, got {other:?}"),
    }
}

#[test]
fn or_condition_nests() {
    let wire = r#"{
        "type": "or",
        "rules": [ { "type": "always" }, { "type": "always" } ]
    }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    match c {
        Condition::Or { rules } => assert_eq!(rules.len(), 2),
        other => panic!("expected Or, got {other:?}"),
    }
}

#[test]
fn not_condition_wraps_one() {
    let wire = r#"{ "type": "not", "rule": { "type": "always" } }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    match c {
        Condition::Not { rule } => assert_eq!(*rule, Condition::Always),
        other => panic!("expected Not, got {other:?}"),
    }
}

#[test]
fn unknown_node_type_becomes_unknown() {
    let wire = r#"{ "type": "regex_set", "patterns": [] }"#;
    let c: Condition = serde_json::from_str(wire).unwrap();
    assert!(matches!(c, Condition::Unknown { tag } if tag == "regex_set"));
}

#[test]
fn unknown_node_type_preserves_tag_through_round_trip() {
    let c = Condition::Unknown {
        tag: "regex_set".to_string(),
    };
    let s = serde_json::to_string(&c).unwrap();
    let back: Condition = serde_json::from_str(&s).unwrap();
    assert_eq!(back, c, "unknown condition tag lost via {s}");
}

#[test]
fn malformed_known_type_errors_rather_than_becoming_unknown() {
    // A recognized node `type` with a structurally invalid body hard-errors at
    // the wire parsing boundary. Runtime rule walking can add broader malformed
    // subtree tolerance without changing this parser contract.
    let wire = r#"{ "type": "and", "rules": "not-an-array" }"#;
    let result: Result<Condition, _> = serde_json::from_str(wire);
    assert!(
        result.is_err(),
        "malformed known type must error, not silently become Unknown"
    );
}

#[test]
fn operator_round_trips_all_19_variants() {
    let cases = [
        ("equals", Operator::Equals),
        ("not_equals", Operator::NotEquals),
        ("gt", Operator::Gt),
        ("gte", Operator::Gte),
        ("lt", Operator::Lt),
        ("lte", Operator::Lte),
        ("in", Operator::In),
        ("not_in", Operator::NotIn),
        ("starts_with", Operator::StartsWith),
        ("ends_with", Operator::EndsWith),
        ("contains", Operator::Contains),
        ("not_contains", Operator::NotContains),
        ("sem_ver_eq", Operator::SemVerEq),
        ("sem_ver_gt", Operator::SemVerGt),
        ("sem_ver_gte", Operator::SemVerGte),
        ("sem_ver_lt", Operator::SemVerLt),
        ("sem_ver_lte", Operator::SemVerLte),
        ("is_set", Operator::IsSet),
        ("is_not_set", Operator::IsNotSet),
    ];
    for (wire, expected) in cases {
        let s = format!("\"{wire}\"");
        let op: Operator = serde_json::from_str(&s).unwrap();
        assert_eq!(op, expected, "wire={wire}");
        let back = serde_json::to_string(&op).unwrap();
        assert_eq!(back, s, "operator round-trip back to wire");
    }
}
