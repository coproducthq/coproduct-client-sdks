use coproduct_core::context::EvaluationContext;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};

#[test]
fn paused_flag_serves_off_variation() {
    let mut flag = bool_flag_with_prereqs("paused-flag", &[]);
    flag.is_paused = true;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "paused-flag", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::Off);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn disabled_flag_serves_off_variation() {
    let mut flag = bool_flag_with_prereqs("disabled-flag", &[]);
    flag.enabled = false;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "disabled-flag", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::Off);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn paused_gate_runs_before_disabled_gate() {
    let mut flag = bool_flag_with_prereqs("both-off", &[]);
    flag.is_paused = true;
    flag.enabled = false;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "both-off", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
}
