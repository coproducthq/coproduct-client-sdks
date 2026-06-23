use coproduct_core::client::CoproductClient;
use coproduct_core::events::{LifecycleEvent, LifecycleHandler};
use std::sync::{Arc, Mutex};

#[derive(Debug, Default)]
struct Counter {
    fired: Mutex<Vec<LifecycleEvent>>,
}

#[async_trait::async_trait]
impl LifecycleHandler for Counter {
    async fn on_event(&self, event: LifecycleEvent) {
        self.fired.lock().unwrap().push(event);
    }
}

#[tokio::test]
async fn add_handler_registers_per_event_type() {
    let client = CoproductClient::test_instance().await;
    let counter: Arc<Counter> = Arc::new(Counter::default());

    let handle_ready = client.add_handler(LifecycleEvent::Ready, counter.clone());
    let handle_stale = client.add_handler(LifecycleEvent::Stale, counter.clone());

    client.fire_event_for_test(LifecycleEvent::Ready).await;
    client.fire_event_for_test(LifecycleEvent::Stale).await;
    client.fire_event_for_test(LifecycleEvent::Fatal).await;

    let fired = counter.fired.lock().unwrap().clone();
    assert_eq!(fired, vec![LifecycleEvent::Ready, LifecycleEvent::Stale]);

    handle_ready.cancel();
    handle_stale.cancel();
}

#[tokio::test]
async fn cancelled_handler_does_not_fire() {
    let client = CoproductClient::test_instance().await;
    let counter: Arc<Counter> = Arc::new(Counter::default());

    let handle = client.add_handler(LifecycleEvent::Ready, counter.clone());
    handle.cancel();

    client.fire_event_for_test(LifecycleEvent::Ready).await;
    assert!(counter.fired.lock().unwrap().is_empty());
}
