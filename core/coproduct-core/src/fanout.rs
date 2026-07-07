//! Observer fanout.
//!
//! Bridges a snapshot or context change to the observer registry. Both entry
//! points re-evaluate only the keys that have at least one registered observer,
//! diff the prior value against the new value, and notify subscribers for the
//! keys that changed. All observer callbacks are awaited outside the registry
//! lock.

use std::sync::Arc;

use crate::context::EvaluationContext;
use crate::eval::evaluate_for_observer;
use crate::observer::{FlagValue, ObserverRegistry};
use crate::snapshot::IndexedSnapshot;

/// Diff each observed key between a prior and a next evaluation point, each a
/// `(snapshot, context)` pair, and notify observers whose value changed. Each side
/// is evaluated with the context a getter would use at that point, so an observer
/// receives the value the next getter call would return. `prev` is `None` on the
/// first snapshot load. All observer callbacks are awaited outside the registry
/// lock
async fn fire_changed(
    registry: &Arc<ObserverRegistry>,
    prev: Option<(&IndexedSnapshot, &EvaluationContext)>,
    next_snapshot: &IndexedSnapshot,
    next_context: &EvaluationContext,
) {
    let mut observed_keys: Vec<String> = registry.observed_keys();
    observed_keys.sort();
    observed_keys.dedup();

    // A sorted vec of pairs rather than a hash map so cross-key delivery order is
    // deterministic (the sorted key order), which keeps multi-key observer tests
    // and bundle emission order stable across runs
    let mut changes: Vec<(String, FlagValue)> = Vec::new();
    for key in observed_keys {
        let new_value = evaluate_for_observer(next_snapshot, &key, next_context);
        let prev_value = prev.and_then(|(snap, ctx)| evaluate_for_observer(snap, &key, ctx));
        match (prev_value, new_value) {
            (Some(prev_v), Some(new_v)) if prev_v == new_v => continue,
            (None, None) => continue,
            (_, Some(new_v)) => changes.push((key, new_v)),
            (Some(_), None) => continue,
        }
    }

    for (key, value) in changes {
        for observer in registry.observers_for(&key) {
            observer.on_change(&key, &value).await;
        }
    }
}

/// Snapshot-swap fanout. Diffs the prior snapshot under the prior context against
/// the next snapshot under the next context, so a value that moved because the
/// swap also replaced the SDK-context layer (edge geo shifting between polls)
/// notifies observers, not only a value that moved because a flag's definition
/// changed. The prior context is what was in effect when observers last saw a
/// value, so the diff is against what was actually delivered
pub async fn fire_changed_for_swap(
    registry: &Arc<ObserverRegistry>,
    prev: Option<(&IndexedSnapshot, &EvaluationContext)>,
    next_snapshot: &IndexedSnapshot,
    next_context: &EvaluationContext,
) {
    fire_changed(registry, prev, next_snapshot, next_context).await;
}

/// Context-change fanout. Used by the identity mutators (identify / set_context /
/// update_attributes / remove_attributes / sign_out) where the snapshot did not
/// move but the targeting key or the user's context attributes did, so both sides
/// diff the same snapshot under the prior and next contexts
pub async fn fire_changed_for_context_swap(
    registry: &Arc<ObserverRegistry>,
    snapshot: &IndexedSnapshot,
    prev_context: &EvaluationContext,
    next_context: &EvaluationContext,
) {
    fire_changed(
        registry,
        Some((snapshot, prev_context)),
        snapshot,
        next_context,
    )
    .await;
}
