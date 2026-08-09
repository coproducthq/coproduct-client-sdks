use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use std::sync::{Arc, Mutex};
use tempfile::TempDir;

#[derive(Debug, Default)]
struct Sink {
    fired: Mutex<usize>,
}

impl TypedFlagObserver for Sink {
    fn on_transition(&self, _revision: u64, _state: &[(String, Option<FlagValue>)]) {
        *self.fired.lock().unwrap() += 1;
    }
}

#[tokio::test]
async fn shutdown_drains_registries_and_persists_snapshot() {
    let tmp = TempDir::new().unwrap();
    let client = CoproductClient::test_instance_with_cache_dir_and_snapshot(
        tmp.path().to_str().unwrap().to_string(),
        coproduct_core::snapshot::test_support::snapshot_with_flags(vec![
            coproduct_core::snapshot::test_support::bool_flag("k", true),
        ]),
    )
    .await;
    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _sub = client.observe_key("k".to_string(), sink.clone());

    // Pre-shutdown the client is live and the observer is registered
    assert!(!client.is_shutdown_for_test());
    assert_eq!(client.observer_count_for_test("k"), 1);

    client.shutdown().await;

    // Post-shutdown the flag is latched, the registries are drained, and the
    // held snapshot has been persisted to the cache directory
    assert!(client.is_shutdown_for_test());
    assert_eq!(client.observer_count_for_test("k"), 0);
    // The cache is scoped per sdk key. This test client is constructed with an
    // empty key, so the persisted snapshot lives under that key's scope
    let persisted = std::fs::read(
        tmp.path()
            .join("coproduct")
            .join(coproduct_core::cache::key_scope(""))
            .join("snapshot.json"),
    )
    .unwrap();
    assert!(!persisted.is_empty());
}
