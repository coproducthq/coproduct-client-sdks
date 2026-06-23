//! Observer fanout.
//!
//! Bridges a snapshot or context change to the observer registry. Both entry
//! points re-evaluate only the keys that have at least one registered observer,
//! diff the prior value against the new value, and notify subscribers for the
//! keys that changed. All observer callbacks are awaited outside the registry
//! lock.

use std::collections::HashMap;
use std::sync::Arc;

use crate::context::EvaluationContext;
use crate::eval::evaluate_for_observer;
use crate::observer::{FlagValue, ObserverRegistry};
use crate::snapshot::IndexedSnapshot;

/// Compute the set of (key, new_value) tuples that changed between two
/// snapshots, restricted to keys with at least one registered observer.
/// Re-evaluation uses the held `EvaluationContext` so observers receive the
/// value the next getter call would return
pub async fn fire_changed_for_swap(
    registry: &Arc<ObserverRegistry>,
    prev: Option<&IndexedSnapshot>,
    next: &IndexedSnapshot,
    context: &EvaluationContext,
) {
    let mut observed_keys: Vec<String> = registry.observed_keys();
    observed_keys.sort();
    observed_keys.dedup();

    let mut changes: HashMap<String, FlagValue> = HashMap::new();
    for key in observed_keys {
        let new_value = evaluate_for_observer(next, &key, context);
        let prev_value = prev
            .map(|snap| evaluate_for_observer(snap, &key, context))
            .unwrap_or(None);
        match (prev_value, new_value) {
            (Some(prev_v), Some(new_v)) if prev_v == new_v => continue,
            (None, None) => continue,
            (_, Some(new_v)) => {
                changes.insert(key, new_v);
            }
            (Some(_), None) => continue,
        }
    }

    for (key, value) in changes {
        for observer in registry.observers_for(&key) {
            observer.on_change(&key, &value).await;
        }
    }
}

/// Re-evaluate every observed key against the SAME snapshot under a NEW
/// `EvaluationContext` and notify observers whose value changed. Used by the
/// identity mutators (identify / set_context / update_attributes /
/// remove_attributes / sign_out) where the snapshot did not move but the
/// targeting key or developer attributes did. Differs from
/// `fire_changed_for_swap` only in that there is no previous snapshot: the diff
/// is purely context-driven and the prior values come from evaluating
/// `snapshot` under the prior context the caller has already captured
pub async fn fire_changed_for_context_swap(
    registry: &Arc<ObserverRegistry>,
    snapshot: &IndexedSnapshot,
    prev_context: &EvaluationContext,
    next_context: &EvaluationContext,
) {
    let mut observed_keys: Vec<String> = registry.observed_keys();
    observed_keys.sort();
    observed_keys.dedup();

    let mut changes: HashMap<String, FlagValue> = HashMap::new();
    for key in observed_keys {
        let prev_value = evaluate_for_observer(snapshot, &key, prev_context);
        let new_value = evaluate_for_observer(snapshot, &key, next_context);
        match (prev_value, new_value) {
            (Some(prev_v), Some(new_v)) if prev_v == new_v => continue,
            (None, None) => continue,
            (_, Some(new_v)) => {
                changes.insert(key, new_v);
            }
            (Some(_), None) => continue,
        }
    }

    for (key, value) in changes {
        for observer in registry.observers_for(&key) {
            observer.on_change(&key, &value).await;
        }
    }
}
