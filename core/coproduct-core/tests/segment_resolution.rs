use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::operators::Operator;
use coproduct_core::snapshot::{Condition, ConditionOutcome, evaluate_condition};
use coproduct_core::snapshot::{Segment, SegmentRule};
use std::collections::HashMap;

fn premium_segment() -> Segment {
    Segment {
        key: "premium_users".into(),
        name: "Premium Users".into(),
        rules: vec![SegmentRule {
            attribute: "plan".into(),
            operator: Operator::Equals,
            values: vec!["premium".to_string()],
        }],
    }
}

fn ctx(plan: &str) -> EvaluationContext {
    let mut map = HashMap::new();
    map.insert("plan".into(), AttributeValue::String(plan.into()));
    EvaluationContext::from_map(map)
}

#[test]
fn segment_reference_matches_when_segment_rule_matches() {
    let mut segments = HashMap::new();
    segments.insert("premium_users".into(), premium_segment());
    let cond = Condition::Segment {
        segment_key: "premium_users".into(),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx("premium"), &segments),
        ConditionOutcome::Match
    );
}

#[test]
fn segment_reference_no_match_when_segment_rule_does_not_match() {
    let mut segments = HashMap::new();
    segments.insert("premium_users".into(), premium_segment());
    let cond = Condition::Segment {
        segment_key: "premium_users".into(),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx("free"), &segments),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn missing_segment_falls_to_no_match_not_circuit_break() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Segment {
        segment_key: "absent_segment".into(),
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx("premium"), &segments),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn missing_segment_inside_and_does_not_short_circuit_to_circuit_break() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::And {
        rules: vec![
            Condition::Always,
            Condition::Segment {
                segment_key: "absent".into(),
            },
        ],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx("free"), &segments),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn missing_segment_inside_or_continues_to_next_branch() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let cond = Condition::Or {
        rules: vec![
            Condition::Segment {
                segment_key: "absent".into(),
            },
            Condition::Always,
        ],
    };
    assert_eq!(
        evaluate_condition(&cond, &ctx("free"), &segments),
        ConditionOutcome::Match
    );
}
