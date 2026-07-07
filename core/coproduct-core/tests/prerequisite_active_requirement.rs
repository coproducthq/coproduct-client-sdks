use coproduct_core::context::EvaluationContext;
use coproduct_core::pipeline::{EvaluationReason, RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{
    bool_flag, bool_flag_with_prereqs, snapshot_with_flags,
};

// A prerequisite gates its dependents. It is satisfied only when the prereq flag
// actively resolves to the required variation, so a paused or disabled prereq
// fails even when the off value it serves equals the required variation. Turning
// a prerequisite off must reliably turn off everything downstream.

fn ctx() -> EvaluationContext {
    EvaluationContext::with_targeting_key("u1")
}

#[test]
fn paused_prerequisite_does_not_satisfy_even_when_its_off_value_matches() {
    let mut prereq = bool_flag("p", true); // enabled it would resolve to "on"
    prereq.is_paused = true; // paused, so it serves the off variation "off"
    // The dependent requires p == "off", which is exactly what a paused p serves
    let parent = bool_flag_with_prereqs("parent", &[("p", "off")]);
    let snapshot = snapshot_with_flags(vec![prereq, parent]);

    let outcome = evaluate(Some(&snapshot), "parent", RequestedType::Bool, &ctx());
    assert_eq!(
        outcome.reason,
        EvaluationReason::PrerequisiteFailed,
        "a paused prerequisite must not satisfy its dependent"
    );
}

#[test]
fn disabled_prerequisite_does_not_satisfy_even_when_its_off_value_matches() {
    let mut prereq = bool_flag("p", true);
    prereq.enabled = false; // disabled, so it serves the off variation "off"
    let parent = bool_flag_with_prereqs("parent", &[("p", "off")]);
    let snapshot = snapshot_with_flags(vec![prereq, parent]);

    let outcome = evaluate(Some(&snapshot), "parent", RequestedType::Bool, &ctx());
    assert_eq!(outcome.reason, EvaluationReason::PrerequisiteFailed);
}

#[test]
fn an_active_prerequisite_that_resolves_to_the_required_variation_satisfies() {
    let prereq = bool_flag("p", true); // enabled, resolves to "on" via fallthrough
    let parent = bool_flag_with_prereqs("parent", &[("p", "on")]);
    let snapshot = snapshot_with_flags(vec![prereq, parent]);

    let outcome = evaluate(Some(&snapshot), "parent", RequestedType::Bool, &ctx());
    assert_ne!(
        outcome.reason,
        EvaluationReason::PrerequisiteFailed,
        "an active prerequisite resolving to the required variation satisfies"
    );
    assert_eq!(outcome.variation_key.as_deref(), Some("on"));
}
