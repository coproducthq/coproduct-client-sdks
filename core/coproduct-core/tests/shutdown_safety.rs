use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::events::{LifecycleEvent, LifecycleHandler};
use coproduct_core::hooks::{EvaluationHook, EvaluationStage, HookContext};
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::secure_store::{SecureStore, SecureStoreError};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

/// Counts every value handed to it so a test can assert an observer stays silent
/// across a post-shutdown swap
#[derive(Debug, Default)]
struct Sink {
    seen: Mutex<u32>,
}

impl TypedFlagObserver for Sink {
    fn on_transition(&self, _revision: u64, _state: &[(String, Option<FlagValue>)]) {
        *self.seen.lock().unwrap() += 1;
    }
}

/// Hook that does nothing, used only to confirm a post-shutdown registration
/// returns a pre-cancelled handle
#[derive(Debug, Default)]
struct NoopHook;

impl EvaluationHook for NoopHook {
    fn on_stage(&self, _stage: EvaluationStage, _ctx: &HookContext) {}
}

/// Lifecycle handler that does nothing, used only to confirm a post-shutdown
/// `add_handler` returns a pre-cancelled handle
#[derive(Debug, Default)]
struct NoopHandler;

#[async_trait::async_trait]
impl LifecycleHandler for NoopHandler {
    async fn on_event(&self, _event: LifecycleEvent) {}
}

/// SecureStore that holds nothing, used to build a client through the cold-start
/// path so identity mutations can be exercised
#[derive(Debug, Default)]
struct EmptyStore;

#[async_trait::async_trait]
impl SecureStore for EmptyStore {
    async fn read(&self, _key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(None)
    }
    async fn write(&self, _key: String, _value: String) -> Result<(), SecureStoreError> {
        Ok(())
    }
}

#[tokio::test]
async fn get_bool_returns_default_after_shutdown() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;

    // Before shutdown the flag resolves to its served value
    assert!(client.get_bool("f".to_string(), false));

    client.shutdown().await;

    // After shutdown every getter returns the caller's default
    assert!(!client.get_bool("f".to_string(), false));
    assert_eq!(
        client.get_string("f".to_string(), "fallback".to_string()),
        "fallback".to_string()
    );
    assert_eq!(client.get_int("f".to_string(), 7), 7);
}

#[tokio::test]
async fn observers_registered_before_shutdown_do_not_fire_after() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "k", true,
        )]))
        .await;

    let sink: Arc<Sink> = Arc::new(Sink::default());
    let _sub = client.observe_key("k".to_string(), sink.clone());

    client.shutdown().await;

    // The swap is gated post-shutdown, so the prior observer never fires again
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("k", false)])))
        .await;

    assert_eq!(*sink.seen.lock().unwrap(), 0);
}

#[tokio::test]
async fn observe_after_shutdown_returns_a_cancelled_subscription() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;
    client.shutdown().await;

    let sink: Arc<Sink> = Arc::new(Sink::default());
    let session = client.observe_key("f".to_string(), sink.clone());

    assert!(session.subscription.is_cancelled());
    assert!(session.seed.iter().all(|(_, value)| value.is_none()));
    assert_eq!(client.observer_count_for_test("f"), 0);
}

#[tokio::test]
async fn add_evaluation_hook_after_shutdown_returns_cancelled_handle() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;
    client.shutdown().await;

    let handle = client.add_evaluation_hook(Arc::new(NoopHook));

    assert!(handle.is_cancelled());
}

#[tokio::test]
async fn add_handler_after_shutdown_returns_cancelled_handle() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;
    client.shutdown().await;

    let sink: Arc<NoopHandler> = Arc::new(NoopHandler);
    let h = client.add_handler(LifecycleEvent::Ready, sink);

    assert!(h.is_cancelled());
}

#[tokio::test]
async fn identity_mutation_after_shutdown_is_suppressed() {
    let client = CoproductClient::for_test_with_store(Arc::new(EmptyStore)).await;
    let before = client.targeting_key_for_test();

    client.shutdown().await;
    client
        .identify("alice".to_string(), HashMap::new(), true)
        .await
        .unwrap();

    // The mutation was suppressed, so the held targeting key is unchanged
    assert_eq!(client.targeting_key_for_test(), before);
}
