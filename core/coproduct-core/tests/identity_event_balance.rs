use coproduct_core::client::CoproductClient;
use coproduct_core::error::IdentityError;
use coproduct_core::events::{LifecycleEvent, LifecycleHandler};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

#[derive(Debug, Default)]
struct Sink {
    events: Mutex<Vec<LifecycleEvent>>,
}

#[async_trait::async_trait]
impl LifecycleHandler for Sink {
    async fn on_event(&self, e: LifecycleEvent) {
        self.events.lock().unwrap().push(e);
    }
}

#[tokio::test]
async fn rejected_identify_emits_no_lifecycle_events() {
    let client = CoproductClient::test_instance().await;
    let sink: Arc<Sink> = Arc::new(Sink::default());

    let handle_reconciling = client.add_handler(LifecycleEvent::Reconciling, sink.clone());
    let handle_context_changed = client.add_handler(LifecycleEvent::ContextChanged, sink.clone());

    let result = client.identify(String::new(), HashMap::new(), true).await;
    assert!(matches!(result, Err(IdentityError::InvalidTargetingKey)));
    assert!(sink.events.lock().unwrap().is_empty());

    handle_reconciling.cancel();
    handle_context_changed.cancel();
}

#[tokio::test]
async fn rejected_set_context_emits_no_lifecycle_events() {
    let client = CoproductClient::test_instance().await;
    let sink: Arc<Sink> = Arc::new(Sink::default());

    let handle_reconciling = client.add_handler(LifecycleEvent::Reconciling, sink.clone());
    let handle_context_changed = client.add_handler(LifecycleEvent::ContextChanged, sink.clone());

    let result = client.set_context(String::new(), HashMap::new()).await;
    assert!(matches!(result, Err(IdentityError::InvalidTargetingKey)));
    assert!(sink.events.lock().unwrap().is_empty());

    handle_reconciling.cancel();
    handle_context_changed.cancel();
}

#[tokio::test]
async fn successful_identify_emits_reconciling_then_context_changed() {
    let client = CoproductClient::test_instance().await;
    let sink: Arc<Sink> = Arc::new(Sink::default());

    let handle_reconciling = client.add_handler(LifecycleEvent::Reconciling, sink.clone());
    let handle_context_changed = client.add_handler(LifecycleEvent::ContextChanged, sink.clone());

    client
        .identify("alice".to_string(), HashMap::new(), true)
        .await
        .unwrap();

    let recorded = sink.events.lock().unwrap().clone();
    assert_eq!(
        recorded,
        vec![LifecycleEvent::Reconciling, LifecycleEvent::ContextChanged]
    );

    handle_reconciling.cancel();
    handle_context_changed.cancel();
}
