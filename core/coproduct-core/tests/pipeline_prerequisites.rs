use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};
use coproduct_core::snapshot::{Flag, Prerequisite};

#[test]
fn satisfied_prereq_proceeds_to_targeting_rules() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("dependent", &[("gate", "on")]),
        bool_flag_with_prereqs("gate", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "dependent", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
    assert_eq!(outcome.reason, EvaluationReason::Fallthrough);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn unsatisfied_prereq_serves_off_with_prerequisite_failed_reason() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("dependent", &[("gate", "treatment")]),
        bool_flag_with_prereqs("gate", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "dependent", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::PrerequisiteFailed);
    assert_eq!(outcome.error_code, None);
}

#[test]
fn missing_prereq_flag_treated_as_failed() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs(
        "dependent",
        &[("ghost-flag", "on")],
    )]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "dependent", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::PrerequisiteFailed);
}

#[test]
fn required_variation_that_does_not_exist_is_failed() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("dependent", &[("gate", "nonexistent-variation")]),
        bool_flag_with_prereqs("gate", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "dependent", RequestedType::Bool, &ctx);
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
    assert_eq!(outcome.reason, EvaluationReason::PrerequisiteFailed);
}

#[test]
fn cycle_between_two_flags_trips_rule_circuit_break() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("a", &[("b", "on")]),
        bool_flag_with_prereqs("b", &[("a", "on")]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let outcome = evaluate(Some(&snapshot), "a", RequestedType::Bool, &ctx);
    assert_eq!(
        outcome.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("off"));
}

#[test]
fn diamond_dependency_memoizes_shared_node() {
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
    assert_eq!(outcome.error_code, None);
}
