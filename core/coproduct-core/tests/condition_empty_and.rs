use coproduct_core::context::EvaluationContext;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};
use coproduct_core::snapshot::{Condition, Coverage, Rollout, TargetingRule};

// An `And` with no rules is vacuously true, so the rule matches every context.
// This pins the intended behavior: degenerate rule data (an empty And plus the
// default full coverage) is a match-all. Write-side validation is expected to
// keep such data off the wire, and this test documents what the evaluator does
// if it ever arrives.
#[test]
fn an_empty_and_matches_everyone() {
    let mut flag = bool_flag_with_prereqs("f", &[]);
    // Fallthrough serves "off" so only the rule can serve "on"
    flag.fallthrough_variation = Some("off".to_string());
    flag.targeting_rules = vec![TargetingRule {
        rule_id: "11111111-1111-1111-1111-111111111111".to_string(),
        condition: Condition::And { rules: vec![] },
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    }];
    let snapshot = snapshot_with_flags(vec![flag]);

    let ctx = EvaluationContext::with_targeting_key("anyone");
    let outcome = evaluate(Some(&snapshot), "f", RequestedType::Bool, &ctx);
    assert_eq!(outcome.reason, EvaluationReason::TargetingMatch);
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
}
