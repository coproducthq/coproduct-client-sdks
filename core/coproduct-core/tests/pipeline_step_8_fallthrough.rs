use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};

#[test]
fn no_rules_serves_fallthrough_variation() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("plain-flag", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "plain-flag", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
    assert_eq!(outcome.reason, EvaluationReason::Fallthrough);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn null_fallthrough_trips_rule_circuit_break() {
    let mut flag = bool_flag_with_prereqs("no-fallthrough", &[]);
    flag.fallthrough_variation = None;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "no-fallthrough", RequestedType::Bool, &ctx);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::Off);
}
