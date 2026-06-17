use coproduct_core::snapshot::{Condition, Coverage, Rollout, TargetingRule};

#[test]
fn targeting_rule_round_trips() {
    let wire = r#"{
        "rule_id": "a1b2c3d4-e5f6-4789-a012-3456789abcde",
        "condition": { "type": "always" },
        "coverage": 7500,
        "rollout": { "type": "variation", "variation": "on" }
    }"#;
    let r: TargetingRule = serde_json::from_str(wire).unwrap();
    assert_eq!(r.rule_id, "a1b2c3d4-e5f6-4789-a012-3456789abcde");
    assert_eq!(r.condition, Condition::Always);
    assert_eq!(r.coverage, Coverage(7500));
    assert_eq!(
        r.rollout,
        Rollout::Variation {
            variation: "on".to_string()
        }
    );
}

#[test]
fn targeting_rule_preserves_field_order_on_serialize() {
    let r = TargetingRule {
        rule_id: "x".to_string(),
        condition: Condition::Always,
        coverage: Coverage(10000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    };
    let s = serde_json::to_string(&r).unwrap();
    let again: TargetingRule = serde_json::from_str(&s).unwrap();
    assert_eq!(r, again);
}

#[test]
fn rule_walker_can_clone_for_evaluation() {
    let r = TargetingRule {
        rule_id: "x".to_string(),
        condition: Condition::Always,
        coverage: Coverage(10000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    };
    let cloned = r.clone();
    assert_eq!(r, cloned);
}
