use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::pipeline::{
    EvaluationReason, MAX_PREREQ_DEPTH, VisitingSet, evaluate_recursive,
};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};

#[test]
fn max_prereq_depth_is_five() {
    assert_eq!(MAX_PREREQ_DEPTH, 5);
}

#[test]
fn depth_at_cap_runs_the_body_and_serves_fallthrough() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("f", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let mut visiting = VisitingSet::new();
    let outcome = evaluate_recursive(&snapshot, "f", &ctx, &mut visiting, MAX_PREREQ_DEPTH);
    assert_eq!(outcome.error_code, None);
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
    assert_eq!(outcome.reason, EvaluationReason::Fallthrough);
}

#[test]
fn depth_past_cap_trips_circuit_break() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("f", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let mut visiting = VisitingSet::new();
    let outcome = evaluate_recursive(&snapshot, "f", &ctx, &mut visiting, MAX_PREREQ_DEPTH + 1);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::Off);
}
