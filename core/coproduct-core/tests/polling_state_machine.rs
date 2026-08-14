use coproduct_core::state::{ProviderState, ProviderStateCell, StateTransition};

#[test]
fn legal_transitions_emit_an_event_and_update_value() {
    let cell = ProviderStateCell::new(ProviderState::NotReady);

    let event = cell.transition(ProviderState::Ready);
    assert_eq!(
        event,
        Some(StateTransition {
            from: ProviderState::NotReady,
            to: ProviderState::Ready,
        })
    );
    assert_eq!(cell.get(), ProviderState::Ready);
}

#[test]
fn idempotent_transition_returns_no_event() {
    let cell = ProviderStateCell::new(ProviderState::Ready);
    assert_eq!(cell.transition(ProviderState::Ready), None);
    assert_eq!(cell.get(), ProviderState::Ready);
}

#[test]
fn fatal_is_terminal_and_rejects_further_transitions() {
    let cell = ProviderStateCell::new(ProviderState::Fatal);
    assert_eq!(cell.transition(ProviderState::Ready), None);
    assert_eq!(cell.get(), ProviderState::Fatal);
}

#[test]
fn full_lifecycle_covers_each_documented_arc() {
    let cell = ProviderStateCell::new(ProviderState::NotReady);

    // NotReady -> Ready
    assert!(cell.transition(ProviderState::Ready).is_some());
    // Ready -> Retrying
    assert!(cell.transition(ProviderState::Retrying).is_some());
    // Retrying -> Stale
    assert!(cell.transition(ProviderState::Stale).is_some());
    // Stale -> Ready
    assert!(cell.transition(ProviderState::Ready).is_some());

    assert_eq!(cell.get(), ProviderState::Ready);
}
