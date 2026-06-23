use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

/// Collects every value handed to it so a test can assert exactly which swaps
/// re-fired the observer
#[derive(Debug, Default)]
struct Sink {
    seen: Mutex<Vec<FlagValue>>,
}

#[async_trait::async_trait]
impl TypedFlagObserver for Sink {
    async fn on_change(&self, _key: &str, value: &FlagValue) {
        self.seen.lock().unwrap().push(value.clone());
    }
}

#[tokio::test]
async fn unchanged_value_across_swap_does_not_refire_observer() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "k", true,
        )]))
        .await;

    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _sub = client.observe_key("k".to_string(), sink.clone());

    // Same evaluated value across the swap: the fanout dedups, so nothing fires
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("k", true)])))
        .await;
    assert!(sink.seen.lock().unwrap().is_empty());

    // Now the value actually changes, so the observer fires exactly once
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("k", false)])))
        .await;
    assert_eq!(*sink.seen.lock().unwrap(), vec![FlagValue::Bool(false)]);
}

#[tokio::test]
async fn unchanged_value_for_one_key_does_not_suppress_other_key() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag("a", true),
        bool_flag("b", true),
    ]))
    .await;

    let sink_a: Arc<Sink> = Arc::new(Sink::default());
    let sink_b: Arc<Sink> = Arc::new(Sink::default());
    let _sub_a = client.observe_key("a".to_string(), sink_a.clone());
    let _sub_b = client.observe_key("b".to_string(), sink_b.clone());

    // a holds steady at true while b moves true -> false
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![
            bool_flag("a", true),
            bool_flag("b", false),
        ])))
        .await;

    assert!(sink_a.seen.lock().unwrap().is_empty());
    assert_eq!(*sink_b.seen.lock().unwrap(), vec![FlagValue::Bool(false)]);
}
