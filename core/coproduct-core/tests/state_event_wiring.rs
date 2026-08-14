use coproduct_core::client::CoproductClient;
use coproduct_core::context::AttributeValue;
use coproduct_core::events::{LifecycleEvent, LifecycleHandler};
use coproduct_core::secure_store::{SecureStore, SecureStoreError};
use coproduct_core::snapshot::test_support::snapshot_with_version;
use coproduct_core::state::ProviderState;
use std::sync::{Arc, Mutex};

#[derive(Debug, Default)]
struct Sink {
    fired: Mutex<Vec<LifecycleEvent>>,
}

#[async_trait::async_trait]
impl LifecycleHandler for Sink {
    async fn on_event(&self, event: LifecycleEvent) {
        self.fired.lock().unwrap().push(event);
    }
}

#[derive(Debug, Default)]
struct NoopStore;

#[async_trait::async_trait]
impl SecureStore for NoopStore {
    async fn read(&self, _key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(None)
    }
    async fn write(&self, _key: String, _value: String) -> Result<(), SecureStoreError> {
        Ok(())
    }
}

#[tokio::test]
async fn state_transition_to_ready_fires_ready_event() {
    let client = CoproductClient::test_instance().await;
    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _h = client.add_handler(LifecycleEvent::Ready, sink.clone());

    client.transition_state_for_test(ProviderState::Ready).await;

    assert_eq!(
        sink.fired.lock().unwrap().as_slice(),
        &[LifecycleEvent::Ready]
    );
}

#[tokio::test]
async fn each_state_maps_to_its_event() {
    let pairs = [
        (ProviderState::Ready, LifecycleEvent::Ready),
        (ProviderState::Retrying, LifecycleEvent::Retrying),
        (ProviderState::Stale, LifecycleEvent::Stale),
        (ProviderState::Fatal, LifecycleEvent::Fatal),
    ];
    for (state, expected) in pairs {
        let client = CoproductClient::test_instance().await;
        let sink: Arc<Sink> = Arc::new(Sink::default());
        let _h = client.add_handler(expected, sink.clone());
        client.transition_state_for_test(state).await;
        assert_eq!(sink.fired.lock().unwrap().as_slice(), &[expected]);
    }
}

#[tokio::test]
async fn newer_snapshot_fires_configuration_changed() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_version(1)).await;
    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _h = client.add_handler(LifecycleEvent::ConfigurationChanged, sink.clone());

    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_version(2)))
        .await;

    assert_eq!(
        sink.fired.lock().unwrap().as_slice(),
        &[LifecycleEvent::ConfigurationChanged]
    );
}

#[tokio::test]
async fn rolled_back_snapshot_also_fires_configuration_changed() {
    // A server-side rollback to a lower version still changes the served flag
    // values, so lifecycle listeners must hear ConfigurationChanged just as the
    // observer fanout fires. The signal keys on a version change, not an increase
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_version(5)).await;
    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _h = client.add_handler(LifecycleEvent::ConfigurationChanged, sink.clone());

    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_version(3)))
        .await;

    assert_eq!(
        sink.fired.lock().unwrap().as_slice(),
        &[LifecycleEvent::ConfigurationChanged]
    );
}

#[tokio::test]
async fn identify_fires_context_changed() {
    let client = CoproductClient::test_instance().await;
    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _h = client.add_handler(LifecycleEvent::ContextChanged, sink.clone());

    client
        .identify("alice".to_string(), std::collections::HashMap::new(), true)
        .await
        .expect("identify with non-empty key succeeds");

    assert!(
        sink.fired
            .lock()
            .unwrap()
            .contains(&LifecycleEvent::ContextChanged),
        "identify must fire ContextChanged"
    );
}

#[tokio::test]
async fn sign_out_fires_context_changed() {
    let client = CoproductClient::test_instance().await;
    client
        .identify("alice".to_string(), std::collections::HashMap::new(), true)
        .await
        .expect("identify with non-empty key succeeds");

    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _h = client.add_handler(LifecycleEvent::ContextChanged, sink.clone());

    client.sign_out().await;

    assert!(
        sink.fired
            .lock()
            .unwrap()
            .contains(&LifecycleEvent::ContextChanged),
        "sign_out must fire ContextChanged"
    );
}

#[tokio::test]
async fn identity_mutators_each_fire_context_changed() {
    let client = CoproductClient::test_instance().await;
    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _h = client.add_handler(LifecycleEvent::ContextChanged, sink.clone());

    client
        .identify("alice".to_string(), std::collections::HashMap::new(), true)
        .await
        .expect("identify with non-empty key succeeds");
    client
        .set_context("bob".to_string(), std::collections::HashMap::new())
        .await
        .expect("set_context with non-empty key succeeds");
    client
        .update_attributes(
            [(
                "plan".to_string(),
                AttributeValue::String("pro".to_string()),
            )]
            .into_iter()
            .collect(),
        )
        .await;
    client.remove_attributes(&["plan".to_string()]).await;
    client.sign_out().await;

    let count = sink
        .fired
        .lock()
        .unwrap()
        .iter()
        .filter(|e| **e == LifecycleEvent::ContextChanged)
        .count();
    assert_eq!(
        count, 5,
        "expected ContextChanged from each identity mutator"
    );
}

#[tokio::test]
async fn poll_failure_fires_retrying_event() {
    let client = CoproductClient::for_test_with_store(Arc::new(NoopStore)).await;
    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _h = client.add_handler(LifecycleEvent::Retrying, sink.clone());

    client.poll_now().await;

    assert!(
        sink.fired
            .lock()
            .unwrap()
            .contains(&LifecycleEvent::Retrying),
        "a failing poll from NotReady must fire Retrying"
    );
}
