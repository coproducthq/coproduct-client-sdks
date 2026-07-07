use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

// The fanout computes a sorted, deduped set of observed keys and must deliver in
// that order. Collecting changes into a sorted vec rather than a hash map keeps
// cross-key delivery order deterministic across runs, so multi-key observer tests
// and bundle emission order stay stable.

#[derive(Debug, Clone)]
struct KeyRecorder {
    seen: Arc<Mutex<Vec<String>>>,
}

#[async_trait::async_trait]
impl TypedFlagObserver for KeyRecorder {
    async fn on_change(&self, key: &str, _value: &FlagValue) {
        self.seen.lock().unwrap().push(key.to_string());
    }
}

#[tokio::test]
async fn fanout_delivers_changed_keys_in_sorted_order() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag("cherry", false),
        bool_flag("apple", false),
        bool_flag("banana", false),
    ]))
    .await;

    let recorder = KeyRecorder {
        seen: Arc::new(Mutex::new(Vec::new())),
    };
    // Register in a deliberately unsorted order so the assertion reflects the
    // fanout's ordering, not the registration order
    let _c = client.observe_key("cherry".to_string(), Arc::new(recorder.clone()));
    let _a = client.observe_key("apple".to_string(), Arc::new(recorder.clone()));
    let _b = client.observe_key("banana".to_string(), Arc::new(recorder.clone()));

    // Every observed flag flips false -> true, so all three fire on the swap
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![
            bool_flag("cherry", true),
            bool_flag("apple", true),
            bool_flag("banana", true),
        ])))
        .await;

    let order = recorder.seen.lock().unwrap().clone();
    assert_eq!(
        order,
        vec!["apple", "banana", "cherry"],
        "cross-key delivery follows sorted key order"
    );
}
