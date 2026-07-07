use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::snapshot::Segment;
use coproduct_core::snapshot::{Condition, ConditionOutcome, evaluate_condition};
use std::collections::HashMap;

fn ctx() -> EvaluationContext {
    let mut map = HashMap::new();
    map.insert("plan".into(), AttributeValue::String("premium".into()));
    EvaluationContext::from_map(map)
}

#[test]
fn unknown_node_type_in_wire_format_decodes_to_unknown_variant() {
    let json = r#"{ "type": "future_node_that_does_not_exist_yet" }"#;
    let cond: Condition = serde_json::from_str(json).expect("tolerant deserialize");
    assert!(matches!(cond, Condition::Unknown { .. }));
}

#[test]
fn unknown_node_evaluates_to_circuit_break() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Unknown {
        tag: "future_node".into(),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx(), &segments),
        ConditionOutcome::CircuitBreak
    );
}

#[test]
fn circuit_break_propagates_through_and() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::And {
        rules: vec![Condition::Always, Condition::Unknown { tag: "x".into() }],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx(), &segments),
        ConditionOutcome::CircuitBreak
    );
}

#[test]
fn circuit_break_propagates_through_or_even_with_later_match() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Or {
        rules: vec![Condition::Unknown { tag: "x".into() }, Condition::Always],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx(), &segments),
        ConditionOutcome::CircuitBreak
    );
}

#[test]
fn circuit_break_propagates_through_not() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Not {
        rule: Box::new(Condition::Unknown { tag: "x".into() }),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx(), &segments),
        ConditionOutcome::CircuitBreak
    );
}

#[test]
fn malformed_attribute_node_decodes_to_unknown_rather_than_panicking() {
    let json = r#"{ "type": "attribute", "attribute": "plan" }"#;
    let cond: Condition = serde_json::from_str(json).expect("tolerant deserialize");
    assert!(matches!(cond, Condition::Unknown { .. }));
}

#[test]
fn attribute_node_with_missing_values_decodes_to_unknown() {
    let json = r#"{ "type": "attribute", "attribute": "plan", "operator": "equals" }"#;
    let cond: Condition = serde_json::from_str(json).expect("tolerant deserialize");
    assert!(matches!(cond, Condition::Unknown { tag } if tag == "attribute"));
}

#[test]
fn attribute_node_with_non_array_values_decodes_to_unknown() {
    let json = r#"{ "type": "attribute", "attribute": "plan", "operator": "equals", "values": "premium" }"#;
    let cond: Condition = serde_json::from_str(json).expect("tolerant deserialize");
    assert!(matches!(cond, Condition::Unknown { tag } if tag == "attribute"));
}

#[test]
fn attribute_node_with_mixed_value_types_decodes_to_unknown() {
    // A malformed RHS holding one valid matching string must not silently become
    // a node that could match. The whole node fails closed to Unknown
    let json = r#"{ "type": "attribute", "attribute": "plan", "operator": "equals", "values": ["premium", 123] }"#;
    let cond: Condition = serde_json::from_str(json).expect("tolerant deserialize");
    assert!(matches!(cond, Condition::Unknown { tag } if tag == "attribute"));
}

#[test]
fn attribute_node_with_all_string_values_decodes_normally() {
    let json = r#"{ "type": "attribute", "attribute": "plan", "operator": "equals", "values": ["premium", "pro"] }"#;
    let cond: Condition = serde_json::from_str(json).expect("tolerant deserialize");
    assert!(matches!(cond, Condition::Attribute { .. }));
}

#[test]
fn attribute_node_with_empty_values_array_is_valid() {
    // An empty array is a valid string array, distinct from a missing or
    // malformed field. Zero-value operators carry an empty values list
    let json =
        r#"{ "type": "attribute", "attribute": "plan", "operator": "is_set", "values": [] }"#;
    let cond: Condition = serde_json::from_str(json).expect("tolerant deserialize");
    assert!(matches!(cond, Condition::Attribute { .. }));
}
