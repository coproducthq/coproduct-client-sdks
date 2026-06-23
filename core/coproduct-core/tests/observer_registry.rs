use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, Subscription, TypedFlagObserver};
use std::sync::{Arc, Mutex};

#[derive(Debug, Default)]
struct Recorder {
    seen: Mutex<Vec<(String, FlagValue)>>,
}

#[async_trait::async_trait]
impl TypedFlagObserver for Recorder {
    async fn on_change(&self, key: &str, value: &FlagValue) {
        self.seen
            .lock()
            .unwrap()
            .push((key.to_string(), value.clone()));
    }
}

#[tokio::test]
async fn observe_single_key_returns_subscription_handle() {
    let client = CoproductClient::test_instance().await;
    let recorder: Arc<Recorder> = Arc::new(Recorder::default());

    let sub: Arc<Subscription> = client.observe_key("new-checkout".to_string(), recorder.clone());

    assert_eq!(sub.keys(), &["new-checkout".to_string()]);
    assert!(!sub.is_cancelled());
}

#[tokio::test]
async fn observe_multi_key_returns_one_subscription_covering_all_keys() {
    let client = CoproductClient::test_instance().await;
    let recorder: Arc<Recorder> = Arc::new(Recorder::default());

    let sub: Arc<Subscription> = client.observe_keys(
        vec!["a".to_string(), "b".to_string(), "c".to_string()],
        recorder.clone(),
    );

    assert_eq!(
        sub.keys(),
        &["a".to_string(), "b".to_string(), "c".to_string()]
    );
}

#[tokio::test]
async fn dropping_subscription_unregisters_the_observer() {
    let client = CoproductClient::test_instance().await;
    let recorder: Arc<Recorder> = Arc::new(Recorder::default());

    let sub = client.observe_key("k".to_string(), recorder.clone());
    assert_eq!(client.observer_count_for_test("k"), 1);
    sub.cancel();
    assert_eq!(client.observer_count_for_test("k"), 0);
}
