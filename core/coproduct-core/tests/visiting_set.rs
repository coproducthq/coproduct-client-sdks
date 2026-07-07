use coproduct_core::pipeline::{EvaluationOutcome, VisitingSet, VisitingState};

#[test]
fn new_visiting_set_is_empty() {
    let set = VisitingSet::new();
    assert!(set.is_empty());
    assert_eq!(set.len(), 0);
}

#[test]
fn mark_visiting_then_resolve_replaces_sentinel() {
    let mut set = VisitingSet::new();
    set.mark_visiting("flag-a");
    assert!(matches!(set.get("flag-a"), Some(VisitingState::Visiting)));

    let outcome = EvaluationOutcome::resolved("on");
    set.resolve("flag-a", outcome.clone());

    match set.get("flag-a") {
        Some(VisitingState::Resolved(o)) => {
            assert_eq!(o.variation_key.as_deref(), Some("on"));
            assert_eq!(
                o.reason,
                coproduct_core::pipeline::EvaluationReason::TargetingMatch
            );
        }
        other => panic!("expected Resolved, got {other:?}"),
    }
}

#[test]
fn cycle_is_detected_when_already_visiting() {
    let mut set = VisitingSet::new();
    set.mark_visiting("flag-a");
    assert!(set.is_visiting("flag-a"));
    assert!(!set.is_visiting("flag-b"));
}
