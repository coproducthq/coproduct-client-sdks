use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::hooks::HookRegistry;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};
use coproduct_core::snapshot::{Condition, Coverage, Rollout, TargetingRule};

fn rule_always_on() -> TargetingRule {
    TargetingRule {
        rule_id: "11111111-1111-1111-1111-111111111111".to_string(),
        condition: Condition::Always,
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    }
}

#[test]
fn rule_matches_returns_targeting_match_reason() {
    let mut flag = bool_flag_with_prereqs("targeted-flag", &[]);
    flag.targeting_rules = vec![rule_always_on()];
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "targeted-flag",
        RequestedType::Bool,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
    assert_eq!(outcome.reason, EvaluationReason::TargetingMatch);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn rule_walker_circuit_break_propagates() {
    let mut flag = bool_flag_with_prereqs("malformed-flag", &[]);
    flag.targeting_rules = vec![TargetingRule {
        rule_id: "22222222-2222-2222-2222-222222222222".to_string(),
        condition: Condition::Unknown {
            tag: "malformed".into(),
        },
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    }];
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "malformed-flag",
        RequestedType::Bool,
        &ctx,
        &registry,
    );
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::Off);
}

#[test]
fn matched_rule_pointing_at_missing_variation_absorbs_to_off() {
    let mut flag = bool_flag_with_prereqs("dangling-flag", &[]);
    flag.targeting_rules = vec![TargetingRule {
        rule_id: "33333333-3333-3333-3333-333333333333".to_string(),
        condition: Condition::Always,
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "ghost".to_string(),
        },
        description: None,
    }];
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "dangling-flag",
        RequestedType::Bool,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::Off);
    assert_eq!(outcome.error_code, None);
}
