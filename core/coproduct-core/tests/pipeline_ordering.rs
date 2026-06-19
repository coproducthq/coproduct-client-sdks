use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::hooks::HookRegistry;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};
use coproduct_core::snapshot::{Condition, Coverage, Rollout, TargetingRule};

fn rule_always_on() -> TargetingRule {
    TargetingRule {
        rule_id: "33333333-3333-3333-3333-333333333333".to_string(),
        condition: Condition::Always,
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    }
}

#[test]
fn step1_beats_step2() {
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(None, "any", RequestedType::Bool, &ctx, &registry);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::ProviderNotReady)
    );
}

#[test]
fn step2_beats_step3() {
    let snapshot = snapshot_with_flags(vec![]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "missing",
        RequestedType::String,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.error_code, Some(EvaluationErrorCode::FlagNotFound));
}

#[test]
fn step3_beats_step4() {
    let mut flag = bool_flag_with_prereqs("paused-bool", &[]);
    flag.is_paused = true;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "paused-bool",
        RequestedType::String,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.error_code, Some(EvaluationErrorCode::TypeMismatch));
}

#[test]
fn step4_beats_step5() {
    let mut flag = bool_flag_with_prereqs("paused-and-disabled", &[]);
    flag.is_paused = true;
    flag.enabled = false;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "paused-and-disabled",
        RequestedType::Bool,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.reason, EvaluationReason::Off);
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
}

#[test]
fn step5_beats_step6() {
    let mut flag = bool_flag_with_prereqs("disabled-with-ghost-prereq", &[("ghost", "on")]);
    flag.enabled = false;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "disabled-with-ghost-prereq",
        RequestedType::Bool,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.reason, EvaluationReason::Off);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn step6_beats_step7() {
    let mut flag = bool_flag_with_prereqs("prereq-then-rule", &[("gate", "treatment")]);
    flag.targeting_rules = vec![rule_always_on()];
    let snapshot = snapshot_with_flags(vec![flag, bool_flag_with_prereqs("gate", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "prereq-then-rule",
        RequestedType::Bool,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.reason, EvaluationReason::PrerequisiteFailed);
}

#[test]
fn step7_beats_step8() {
    let mut flag = bool_flag_with_prereqs("rule-wins", &[]);
    flag.targeting_rules = vec![rule_always_on()];
    flag.fallthrough_variation = Some("off".to_string());
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let registry = HookRegistry::default();
    let outcome = evaluate(
        Some(&snapshot),
        "rule-wins",
        RequestedType::Bool,
        &ctx,
        &registry,
    );
    assert_eq!(outcome.reason, EvaluationReason::TargetingMatch);
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
}
