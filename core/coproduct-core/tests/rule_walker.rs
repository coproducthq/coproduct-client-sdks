use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::operators::Operator;
use coproduct_core::rule_walker::{RuleWalkResult, walk_rules};
use coproduct_core::snapshot::Condition;
use coproduct_core::snapshot::{
    Coverage, Flag, FlagType, Rollout, Segment, SegmentRule, TargetingRule, Variation,
    VariationValue, WeightedVariation,
};
use std::collections::HashMap;

fn ctx_with(key: &str, plan: Option<&str>) -> EvaluationContext {
    let mut map = HashMap::new();
    map.insert("targetingKey".into(), AttributeValue::String(key.into()));
    if let Some(p) = plan {
        map.insert("plan".into(), AttributeValue::String(p.into()));
    }
    EvaluationContext::from_map(map)
}

fn flag_with_rules(rules: Vec<TargetingRule>) -> Flag {
    Flag {
        key: "test_flag".into(),
        r#type: FlagType::Bool,
        enabled: true,
        is_paused: false,
        variations: vec![
            Variation {
                key: "on".into(),
                value: VariationValue::Bool(true),
                name: None,
            },
            Variation {
                key: "off".into(),
                value: VariationValue::Bool(false),
                name: None,
            },
        ],
        off_variation: Some("off".into()),
        fallthrough_variation: Some("off".into()),
        targeting_rules: rules,
        prerequisites: vec![],
        experiment: None,
    }
}

fn premium_rule(id: &str, coverage: u32, variation: &str) -> TargetingRule {
    TargetingRule {
        rule_id: id.into(),
        condition: Condition::Attribute {
            attribute: "plan".into(),
            operator: Operator::Equals,
            values: vec!["premium".to_string()],
        },
        coverage: Coverage(coverage),
        rollout: Rollout::Variation {
            variation: variation.into(),
        },
        description: None,
    }
}

#[test]
fn rule_walker_returns_fallthrough_when_no_rules() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![]);
    let ctx = ctx_with("user_1", Some("premium"));
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::Fallthrough
    );
}

#[test]
fn rule_walker_returns_rule_match_when_condition_and_coverage_in() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![premium_rule(
        "00000000-0000-4000-8000-000000000001",
        10_000,
        "on",
    )]);
    let ctx = ctx_with("user_1", Some("premium"));
    match walk_rules(&flag, &ctx, &segments) {
        RuleWalkResult::Match { rule_id, variation } => {
            assert_eq!(rule_id, "00000000-0000-4000-8000-000000000001");
            assert_eq!(variation, "on");
        }
        other => panic!("expected Match, got {other:?}"),
    }
}

#[test]
fn rule_walker_falls_through_when_condition_does_not_match() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![premium_rule(
        "00000000-0000-4000-8000-000000000001",
        10_000,
        "on",
    )]);
    let ctx = ctx_with("user_1", Some("free"));
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::Fallthrough
    );
}

#[test]
fn rule_walker_falls_through_when_user_out_of_coverage() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![premium_rule(
        "00000000-0000-4000-8000-000000000001",
        0,
        "on",
    )]);
    let ctx = ctx_with("user_1", Some("premium"));
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::Fallthrough
    );
}

#[test]
fn rule_walker_first_match_wins_top_to_bottom() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![
        premium_rule("00000000-0000-4000-8000-000000000001", 10_000, "on"),
        premium_rule("00000000-0000-4000-8000-000000000002", 10_000, "off"),
    ]);
    let ctx = ctx_with("user_1", Some("premium"));
    match walk_rules(&flag, &ctx, &segments) {
        RuleWalkResult::Match { variation, .. } => assert_eq!(variation, "on"),
        other => panic!("expected first rule to win, got {other:?}"),
    }
}

#[test]
fn rule_walker_circuit_break_propagates() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let mut flag = flag_with_rules(vec![]);
    flag.targeting_rules.push(TargetingRule {
        rule_id: "00000000-0000-4000-8000-000000000003".into(),
        condition: Condition::Unknown {
            tag: "future_node".into(),
        },
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".into(),
        },
        description: None,
    });
    let ctx = ctx_with("user_1", Some("premium"));
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::CircuitBreak
    );
}

fn always_rule_with_rollout(id: &str, rollout: Rollout) -> TargetingRule {
    TargetingRule {
        rule_id: id.into(),
        condition: Condition::Always,
        coverage: Coverage(10_000),
        rollout,
        description: None,
    }
}

#[test]
fn rule_walker_weighted_rollout_full_weight_to_first_variation() {
    // Weights [100, 0] put the entire variant space below the first cursor, so
    // every user lands on the first variation regardless of their variant bucket
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![always_rule_with_rollout(
        "00000000-0000-4000-8000-000000000010",
        Rollout::Weights {
            weights: vec![
                WeightedVariation {
                    variation_key: "on".into(),
                    percentage: 100,
                },
                WeightedVariation {
                    variation_key: "off".into(),
                    percentage: 0,
                },
            ],
        },
    )]);
    let ctx = ctx_with("user_1", None);
    match walk_rules(&flag, &ctx, &segments) {
        RuleWalkResult::Match { variation, .. } => assert_eq!(variation, "on"),
        other => panic!("expected weighted match to on, got {other:?}"),
    }
}

#[test]
fn rule_walker_weighted_rollout_full_weight_to_second_variation() {
    // Weights [0, 100] leave the first cursor at zero so no bucket falls under
    // it, and every user lands on the second variation
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![always_rule_with_rollout(
        "00000000-0000-4000-8000-000000000011",
        Rollout::Weights {
            weights: vec![
                WeightedVariation {
                    variation_key: "on".into(),
                    percentage: 0,
                },
                WeightedVariation {
                    variation_key: "off".into(),
                    percentage: 100,
                },
            ],
        },
    )]);
    let ctx = ctx_with("user_2", None);
    match walk_rules(&flag, &ctx, &segments) {
        RuleWalkResult::Match { variation, .. } => assert_eq!(variation, "off"),
        other => panic!("expected weighted match to off, got {other:?}"),
    }
}

#[test]
fn rule_walker_unknown_rollout_falls_through() {
    // An unrecognized rollout shape yields no assignment, so the matched rule
    // does not include the user and the walk falls through
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![always_rule_with_rollout(
        "00000000-0000-4000-8000-000000000012",
        Rollout::Unknown,
    )]);
    let ctx = ctx_with("user_1", None);
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::Fallthrough
    );
}

// Regression for the construction-path bypass: a flag deserialized straight from
// the wire, never routed through snapshot ingestion, must still fail closed when
// a later rule carries an unknown condition node. Rule 1 (always -> on) would
// otherwise match first, so a walker that keyed off cached ingestion state would
// return Match here instead of CircuitBreak
#[test]
fn rule_walker_fails_closed_on_directly_deserialized_flag_with_unknown_node() {
    let flag: Flag = serde_json::from_str(
        r#"{
            "key": "f",
            "type": "BOOL",
            "enabled": true,
            "isPaused": false,
            "variations": [
                { "key": "on", "value": true },
                { "key": "off", "value": false }
            ],
            "offVariation": "off",
            "fallthroughVariation": "off",
            "targetingRules": [
                {
                    "rule_id": "00000000-0000-4000-8000-0000000000a1",
                    "condition": { "type": "always" },
                    "coverage": 10000,
                    "rollout": { "type": "variation", "variation": "on" }
                },
                {
                    "rule_id": "00000000-0000-4000-8000-0000000000a2",
                    "condition": { "type": "future_op_v9" },
                    "coverage": 10000,
                    "rollout": { "type": "variation", "variation": "off" }
                }
            ],
            "prerequisites": [],
            "experiment": null
        }"#,
    )
    .expect("flag deserializes");
    let segments: HashMap<String, Segment> = HashMap::new();
    let ctx = ctx_with("user_1", None);
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::CircuitBreak,
        "an unknown node in a later rule fails the flag closed even for a directly deserialized flag"
    );
}

// An unknown operator on an otherwise valid attribute condition fails the whole
// flag closed up front, exactly like an unknown node type. Rule 1 (always -> on)
// matches first, so a walker that only tripped when evaluation reached the
// unknown operator would return Match here. The strict scan must catch the
// unknown operator before any rule runs, so every context fails closed
// regardless of rule order
#[test]
fn rule_walker_fails_closed_on_unknown_operator_in_later_rule() {
    let segments: HashMap<String, Segment> = HashMap::new();
    let flag = flag_with_rules(vec![
        always_rule_with_rollout(
            "00000000-0000-4000-8000-0000000000b1",
            Rollout::Variation {
                variation: "on".into(),
            },
        ),
        TargetingRule {
            rule_id: "00000000-0000-4000-8000-0000000000b2".into(),
            condition: Condition::Attribute {
                attribute: "plan".into(),
                operator: Operator::Unknown,
                values: vec!["premium".to_string()],
            },
            coverage: Coverage(10_000),
            rollout: Rollout::Variation {
                variation: "off".into(),
            },
            description: None,
        },
    ]);
    let ctx = ctx_with("user_1", Some("premium"));
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::CircuitBreak,
        "an unknown operator in a later rule fails the flag closed even when an earlier rule matches"
    );
}

// The strict scan resolves referenced segments too: an unknown operator inside a
// segment a rule points at fails the whole flag closed up front, so an inline
// unknown operator and a segment-embedded one behave identically
#[test]
fn rule_walker_fails_closed_on_unknown_operator_in_referenced_segment() {
    let mut segments: HashMap<String, Segment> = HashMap::new();
    segments.insert(
        "beta".into(),
        Segment {
            key: "beta".into(),
            name: "Beta".into(),
            rules: vec![SegmentRule {
                attribute: "plan".into(),
                operator: Operator::Unknown,
                values: vec!["premium".to_string()],
            }],
        },
    );
    let flag = flag_with_rules(vec![
        always_rule_with_rollout(
            "00000000-0000-4000-8000-0000000000c1",
            Rollout::Variation {
                variation: "on".into(),
            },
        ),
        TargetingRule {
            rule_id: "00000000-0000-4000-8000-0000000000c2".into(),
            condition: Condition::Segment {
                segment_key: "beta".into(),
            },
            coverage: Coverage(10_000),
            rollout: Rollout::Variation {
                variation: "off".into(),
            },
            description: None,
        },
    ]);
    let ctx = ctx_with("user_1", Some("premium"));
    assert_eq!(
        walk_rules(&flag, &ctx, &segments),
        RuleWalkResult::CircuitBreak,
        "an unknown operator inside a referenced segment fails the flag closed"
    );
}
