//! Observer fanout.
//!
//! Turns one accepted transition into at most one delivery per subscription. A
//! transition is a pair of immutable evaluation points captured at commit, so a
//! fanout that runs after the coordinator gate is released still evaluates the
//! state that transition committed rather than whatever is live later. Each
//! delivery carries the subscription's complete current state, so a newer batch
//! fully supersedes an older one.

use std::sync::Arc;

use crate::context::EvaluationContext;
use crate::eval::evaluate_for_observer;
use crate::observer::{FlagValue, ObserverRegistry};
use crate::snapshot::IndexedSnapshot;

/// One side of a transition: the snapshot in effect and the context a getter
/// would evaluate with. `snapshot` is `None` before the first load and after a
/// revoked key clears the held snapshot, which is what makes an unavailable
/// transition representable
#[derive(Clone)]
pub struct EvaluationPoint {
    pub snapshot: Option<Arc<IndexedSnapshot>>,
    pub context: EvaluationContext,
}

impl EvaluationPoint {
    /// Projected value of `key` at this point. `None` means unavailable: no
    /// snapshot, no such flag, or a flag that resolves no usable variation of
    /// its declared type
    pub fn value_for(&self, key: &str) -> Option<FlagValue> {
        self.snapshot
            .as_ref()
            .and_then(|snapshot| evaluate_for_observer(snapshot, key, &self.context))
    }
}

/// Complete projected state for `keys` at `point`, in the given key order. Used
/// both for a registration seed and for a delivered batch, so the two shapes
/// cannot drift
pub fn project_state(point: &EvaluationPoint, keys: &[String]) -> Vec<(String, Option<FlagValue>)> {
    keys.iter()
        .map(|key| (key.clone(), point.value_for(key)))
        .collect()
}

/// Deliver `revision` to every subscription with at least one changed key. A
/// changed key is one whose projected value differs between the points, which
/// covers a value move, an appearance (`None -> Some`), and a disappearance
/// (`Some -> None`). Delivery is synchronous and runs outside the registry lock
pub fn fire_transition(
    registry: &Arc<ObserverRegistry>,
    revision: u64,
    prev: &EvaluationPoint,
    next: &EvaluationPoint,
) {
    let mut targets = Vec::new();
    for (keys, observer, lane) in registry.subscription_snapshot() {
        let state = project_state(next, &keys);
        let changed = state
            .iter()
            .any(|(key, value)| *value != prev.value_for(key));
        if changed {
            targets.push((lane, observer, state));
        }
    }
    registry.deliver_to(revision, targets);
}
