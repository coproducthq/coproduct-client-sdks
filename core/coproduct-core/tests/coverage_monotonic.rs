use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::rule_walker::{RuleWalkResult, walk_rules};
use coproduct_core::snapshot::Condition;
use coproduct_core::snapshot::{Coverage, Flag, FlagType, Rollout, TargetingRule};
use std::collections::HashMap;

fn flag_with_coverage(coverage: u32) -> Flag {
    Flag {
        key: "f".into(),
        r#type: FlagType::Bool,
        enabled: true,
        is_paused: false,
        variations: vec![],
        off_variation: Some("off".into()),
        fallthrough_variation: Some("off".into()),
        targeting_rules: vec![TargetingRule {
            rule_id: "11111111-1111-4111-8111-111111111111".into(),
            condition: Condition::Always,
            coverage: Coverage(coverage),
            rollout: Rollout::Variation {
                variation: "on".into(),
            },
            description: None,
        }],
        prerequisites: vec![],
        experiment: None,
    }
}

fn ctx_for_user(uid: usize) -> EvaluationContext {
    let mut map = HashMap::new();
    map.insert(
        "targetingKey".into(),
        AttributeValue::String(format!("user_{uid}")),
    );
    EvaluationContext::from_map(map)
}

fn included(flag: &Flag, ctx: &EvaluationContext) -> bool {
    matches!(
        walk_rules(flag, ctx, &HashMap::new()),
        RuleWalkResult::Match { .. }
    )
}

#[test]
fn growing_coverage_keeps_every_prior_in_user_in() {
    // The two-bucket gate keeps the rollout bucket per user stable because the
    // rule_id is fixed, so growing coverage strictly expands the included set and
    // nobody flips out
    let small = flag_with_coverage(2_500);
    let big = flag_with_coverage(5_000);
    let mut included_in_small = 0usize;
    let mut switched_out = 0usize;
    for uid in 0..10_000 {
        let ctx = ctx_for_user(uid);
        if included(&small, &ctx) {
            included_in_small += 1;
            if !included(&big, &ctx) {
                switched_out += 1;
            }
        }
    }
    assert_eq!(switched_out, 0, "monotonic expansion violated");
    assert!(
        (2_300..=2_700).contains(&included_in_small),
        "inclusion at 25% was {included_in_small}, expected near 2500"
    );
}

#[test]
fn shrinking_coverage_only_drops_users_never_swaps() {
    let big = flag_with_coverage(7_500);
    let small = flag_with_coverage(2_500);
    let mut new_inclusions = 0usize;
    for uid in 0..5_000 {
        let ctx = ctx_for_user(uid);
        if included(&small, &ctx) && !included(&big, &ctx) {
            new_inclusions += 1;
        }
    }
    assert_eq!(new_inclusions, 0, "shrinking coverage added new users");
}
