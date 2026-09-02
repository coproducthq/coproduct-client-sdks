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
async fn shutdown_drains_registries_and_leaves_the_cached_envelope_intact() {
    let tmp = TempDir::new().unwrap();
    let dir = tmp.path().to_str().unwrap().to_string();

    // The poll 200 handler persists the whole response body, sdkContext
    // included. Staging exactly that shape is what makes this assertion cover
    // what a real cache holds after a successful poll
    let envelope = br#"{"snapshot":{"schemaVersion":1,"version":7,"generatedAt":"2026-09-01T00:00:00Z","environment":{"slug":"production","projectKey":"app"},"flags":[],"segments":[]},"sdkContext":{"country":"DE","continent":"EU","regionCode":"BE","city":"Berlin","timezone":"Europe/Berlin"}}"#;
    coproduct_core::cache::write_snapshot(&dir, "", envelope).unwrap();

    let client = CoproductClient::test_instance_with_cache_dir_and_snapshot(
        dir.clone(),
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

    // Post-shutdown the flag is latched and the registries are drained
    assert!(client.is_shutdown_for_test());
    assert_eq!(client.observer_count_for_test("k"), 0);

    // The cache is scoped per sdk key and this test client carries an empty
    // key. Shutdown must leave the staged envelope alone. A rewrite that drops
    // sdkContext strands geo targeting on the next cold start, because the
    // rehydrated context has no country, city, or region_code until the first
    // poll lands
    let after = coproduct_core::cache::read_snapshot(&dir, "")
        .unwrap()
        .expect("the staged cache file must still exist after shutdown");
    let parsed: serde_json::Value = serde_json::from_slice(&after).unwrap();
    assert!(
        parsed.get("sdkContext").is_some(),
        "shutdown dropped sdkContext from the persisted envelope"
    );
    assert_eq!(parsed["sdkContext"]["country"], "DE");
}
