use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};

#[test]
fn step1_no_snapshot_returns_provider_not_ready() {
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(None, "any-flag", RequestedType::Bool, &ctx);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::ProviderNotReady)
    );
    assert_eq!(outcome.reason, EvaluationReason::Error);
    assert!(outcome.variation_key.is_none());
}

#[test]
fn step2_missing_flag_returns_flag_not_found() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("real-flag", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "missing-flag", RequestedType::Bool, &ctx);
    assert_eq!(outcome.error_code, Some(EvaluationErrorCode::FlagNotFound));
}

#[test]
fn step3_type_mismatch_returns_type_mismatch() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("bool-flag", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "bool-flag", RequestedType::String, &ctx);
    assert_eq!(outcome.error_code, Some(EvaluationErrorCode::TypeMismatch));
}
