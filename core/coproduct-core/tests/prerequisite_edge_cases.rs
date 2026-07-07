use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};
use coproduct_core::snapshot::{Flag, Prerequisite};

#[test]
fn self_cycle_short_circuits() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("self", &[("self", "on")])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "self", RequestedType::Bool, &ctx);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
}

#[test]
fn three_node_cycle_short_circuits() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("a", &[("b", "on")]),
        bool_flag_with_prereqs("b", &[("c", "on")]),
        bool_flag_with_prereqs("c", &[("a", "on")]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "a", RequestedType::Bool, &ctx);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );
}

#[test]
fn depth_exactly_at_boundary_passes() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("f0", &[("f1", "on")]),
        bool_flag_with_prereqs("f1", &[("f2", "on")]),
        bool_flag_with_prereqs("f2", &[("f3", "on")]),
        bool_flag_with_prereqs("f3", &[("f4", "on")]),
        bool_flag_with_prereqs("f4", &[("f5", "on")]),
        bool_flag_with_prereqs("f5", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "f0", RequestedType::Bool, &ctx);
    assert_eq!(outcome.error_code, None);
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
}

#[test]
fn depth_just_past_boundary_circuit_breaks() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("f0", &[("f1", "on")]),
        bool_flag_with_prereqs("f1", &[("f2", "on")]),
        bool_flag_with_prereqs("f2", &[("f3", "on")]),
        bool_flag_with_prereqs("f3", &[("f4", "on")]),
        bool_flag_with_prereqs("f4", &[("f5", "on")]),
        bool_flag_with_prereqs("f5", &[("f6", "on")]),
        bool_flag_with_prereqs("f6", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "f0", RequestedType::Bool, &ctx);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );
}

#[test]
fn diamond_memoization_returns_consistent_result() {
    let snapshot = snapshot_with_flags(vec![
        Flag {
            prerequisites: vec![
                Prerequisite {
                    flag_key: "b".to_string(),
                    variation: "on".to_string(),
                },
                Prerequisite {
                    flag_key: "c".to_string(),
                    variation: "on".to_string(),
                },
            ],
            ..bool_flag_with_prereqs("a", &[])
        },
        bool_flag_with_prereqs("b", &[("d", "on")]),
        bool_flag_with_prereqs("c", &[("d", "on")]),
        bool_flag_with_prereqs("d", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "a", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
    assert_eq!(outcome.reason, EvaluationReason::Fallthrough);
}

#[test]
fn missing_prereq_does_not_circuit_break() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs(
        "depends-on-ghost",
        &[("ghost", "on")],
    )]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(
        Some(&snapshot),
        "depends-on-ghost",
        RequestedType::Bool,
        &ctx,
    );
    assert_eq!(outcome.reason, EvaluationReason::PrerequisiteFailed);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn missing_required_variation_does_not_circuit_break() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("dependent", &[("gate", "phantom")]),
        bool_flag_with_prereqs("gate", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "dependent", RequestedType::Bool, &ctx);
    assert_eq!(outcome.reason, EvaluationReason::PrerequisiteFailed);
    assert_eq!(outcome.error_code, None);
}
