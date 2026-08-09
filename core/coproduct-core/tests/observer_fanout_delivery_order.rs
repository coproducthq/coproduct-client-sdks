use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

// A delivery carries the subscription's complete current state for every key it
// registered, in registration order, so a host that builds a bundle from a batch
// gets a stable key order. Cross-subscription order is subscription id order,
// which is registration order

#[derive(Debug, Clone)]
struct BatchRecorder {
    label: String,
    seen: Arc<Mutex<Vec<(String, Vec<String>)>>>,
}

impl TypedFlagObserver for BatchRecorder {
    fn on_transition(&self, _revision: u64, state: &[(String, Option<FlagValue>)]) {
        let keys = state.iter().map(|(key, _)| key.clone()).collect();
        self.seen.lock().unwrap().push((self.label.clone(), keys));
    }
}

#[tokio::test]
async fn a_batch_carries_every_subscribed_key_in_registration_order() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag("cherry", false),
        bool_flag("apple", false),
        bool_flag("banana", false),
    ]))
    .await;

    let seen = Arc::new(Mutex::new(Vec::new()));
    // Register a deliberately unsorted key list so the assertion reflects the
    // batch's own ordering rule, not incidental sorting
    let _bundle = client.observe_keys(
        vec![
            "cherry".to_string(),
            "apple".to_string(),
            "banana".to_string(),
        ],
        Arc::new(BatchRecorder {
            label: "bundle".to_string(),
            seen: seen.clone(),
        }),
    );

    // Only apple moves, and the batch still carries all three keys
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![
            bool_flag("cherry", false),
            bool_flag("apple", true),
            bool_flag("banana", false),
        ])))
        .await;

    let seen = seen.lock().unwrap();
    assert_eq!(seen.len(), 1, "one delivery for the one changed transition");
    assert_eq!(seen[0].1, vec!["cherry", "apple", "banana"]);
}

#[tokio::test]
async fn subscriptions_are_delivered_in_registration_order() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "k", false,
        )]))
        .await;

    let seen = Arc::new(Mutex::new(Vec::new()));
    // Retain every session for the whole test: dropping one would cancel its
    // subscription and silence that recorder
    let _sessions: Vec<_> = ["first", "second", "third"]
        .into_iter()
        .map(|label| {
            client.observe_key(
                "k".to_string(),
                Arc::new(BatchRecorder {
                    label: label.to_string(),
                    seen: seen.clone(),
                }),
            )
        })
        .collect();

    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("k", true)])))
        .await;

    let labels: Vec<String> = seen
        .lock()
        .unwrap()
        .iter()
        .map(|(l, _)| l.clone())
        .collect();
    assert_eq!(labels, vec!["first", "second", "third"]);
}
