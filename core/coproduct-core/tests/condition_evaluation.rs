use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::operators::Operator;
use coproduct_core::snapshot::Segment;
use coproduct_core::snapshot::{Condition, ConditionOutcome, evaluate_condition};
use std::collections::HashMap;

fn ctx_with(attrs: &[(&str, AttributeValue)]) -> EvaluationContext {
    let mut map = HashMap::new();
    for (k, v) in attrs {
        map.insert((*k).to_string(), v.clone());
    }
    EvaluationContext::from_map(map)
}

#[test]
fn always_node_returns_match() {
    let ctx = ctx_with(&[]);
    let segments: HashMap<String, Segment> = HashMap::new();
    assert_eq!(
        evaluate_condition(&Condition::Always, &ctx, &segments),
        ConditionOutcome::Match
    );
}

#[test]
fn attribute_eq_match() {
    let ctx = ctx_with(&[("plan", AttributeValue::String("premium".into()))]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Attribute {
        attribute: "plan".into(),
        operator: Operator::Equals,
        values: vec!["premium".to_string()],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Match
    );
}

#[test]
fn attribute_eq_indeterminate_on_missing_attribute() {
    let ctx = ctx_with(&[]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Attribute {
        attribute: "plan".into(),
        operator: Operator::Equals,
        values: vec!["premium".to_string()],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn attribute_eq_nomatch_on_disagreement() {
    let ctx = ctx_with(&[("plan", AttributeValue::String("free".into()))]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Attribute {
        attribute: "plan".into(),
        operator: Operator::Equals,
        values: vec!["premium".to_string()],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn and_node_short_circuits_on_nomatch() {
    let ctx = ctx_with(&[("plan", AttributeValue::String("premium".into()))]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::And {
        rules: vec![
            Condition::Attribute {
                attribute: "plan".into(),
                operator: Operator::Equals,
                values: vec!["free".to_string()],
            },
            Condition::Always,
        ],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn and_node_propagates_indeterminate_when_no_nomatch_present() {
    let ctx = ctx_with(&[]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::And {
        rules: vec![
            Condition::Always,
            Condition::Attribute {
                attribute: "plan".into(),
                operator: Operator::Equals,
                values: vec!["premium".to_string()],
            },
        ],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn or_node_short_circuits_on_match() {
    let ctx = ctx_with(&[]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Or {
        rules: vec![Condition::Always],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Match
    );
}

#[test]
fn or_node_propagates_indeterminate_when_no_match_present() {
    let ctx = ctx_with(&[("plan", AttributeValue::String("free".into()))]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Or {
        rules: vec![
            Condition::Attribute {
                attribute: "plan".into(),
                operator: Operator::Equals,
                values: vec!["premium".to_string()],
            },
            Condition::Attribute {
                attribute: "region".into(),
                operator: Operator::Equals,
                values: vec!["US".to_string()],
            },
        ],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn not_flips_match_to_nomatch() {
    let ctx = ctx_with(&[]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Not {
        rule: Box::new(Condition::Always),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn not_flips_genuine_nomatch_to_match() {
    let ctx = ctx_with(&[("plan", AttributeValue::String("free".into()))]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let inner = Condition::Attribute {
        attribute: "plan".into(),
        operator: Operator::Equals,
        values: vec!["premium".to_string()],
    };
    let cond = Condition::Not {
        rule: Box::new(inner),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Match
    );
}

#[test]
fn not_preserves_indeterminate_for_missing_attribute() {
    let ctx = ctx_with(&[]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let inner = Condition::Attribute {
        attribute: "plan".into(),
        operator: Operator::Equals,
        values: vec!["premium".to_string()],
    };
    let cond = Condition::Not {
        rule: Box::new(inner),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn double_negation_preserves_match() {
    let ctx = ctx_with(&[("plan", AttributeValue::String("premium".into()))]);
    let segments: HashMap<String, Segment> = HashMap::new();
    let inner = Condition::Attribute {
        attribute: "plan".into(),
        operator: Operator::Equals,
        values: vec!["premium".to_string()],
    };
    let cond = Condition::Not {
        rule: Box::new(Condition::Not {
            rule: Box::new(inner),
        }),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx, &segments),
        ConditionOutcome::Match
    );
}
