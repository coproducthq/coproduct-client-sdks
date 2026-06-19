use coproduct_core::client::CoproductClient;
use coproduct_core::context::EvaluationContext;
use coproduct_core::pipeline::EvaluationReason;
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};

#[test]
fn evaluate_bool_outcome_returns_targeting_outcome() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("ok-flag", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let client = CoproductClient::for_testing(snapshot);

    let outcome = client.evaluate_bool_outcome("ok-flag", false, &ctx);

    assert!(outcome.value);
    assert_eq!(outcome.variant.as_deref(), Some("on"));
    assert_eq!(outcome.reason, EvaluationReason::Fallthrough);
    assert!(outcome.error_code.is_none());
    assert_eq!(outcome.flag_key, "ok-flag");
}

#[test]
fn evaluate_bool_outcome_returns_default_on_flag_not_found() {
    let snapshot = snapshot_with_flags(vec![]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let client = CoproductClient::for_testing(snapshot);

    let outcome = client.evaluate_bool_outcome("ghost", true, &ctx);

    assert!(outcome.value);
    assert!(outcome.variant.is_none());
    assert!(outcome.error_code.is_some());
}
