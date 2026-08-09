use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use std::sync::{Arc, Mutex};

#[derive(Debug, Default)]
struct Recorder {
    seen: Mutex<Vec<(String, FlagValue)>>,
}

impl TypedFlagObserver for Recorder {
    fn on_transition(&self, _revision: u64, state: &[(String, Option<FlagValue>)]) {
        let mut seen = self.seen.lock().unwrap();
        for (key, value) in state {
            if let Some(value) = value {
                seen.push((key.clone(), value.clone()));
            }
        }
    }
}

#[tokio::test]
async fn observe_single_key_returns_an_observer_session() {
    let client = CoproductClient::test_instance().await;
    let recorder: Arc<Recorder> = Arc::new(Recorder::default());

    let session = client.observe_key("new-checkout".to_string(), recorder.clone());

    assert_eq!(session.subscription.keys(), &["new-checkout".to_string()]);
    assert!(!session.subscription.is_cancelled());
}

#[tokio::test]
async fn observe_multi_key_returns_one_session_covering_all_keys() {
    let client = CoproductClient::test_instance().await;
    let recorder: Arc<Recorder> = Arc::new(Recorder::default());

    let session = client.observe_keys(
        vec!["a".to_string(), "b".to_string(), "c".to_string()],
        recorder.clone(),
    );

    assert_eq!(
        session.subscription.keys(),
        &["a".to_string(), "b".to_string(), "c".to_string()]
    );
}

#[tokio::test]
async fn dropping_subscription_unregisters_the_observer() {
    let client = CoproductClient::test_instance().await;
    let recorder: Arc<Recorder> = Arc::new(Recorder::default());

    let session = client.observe_key("k".to_string(), recorder.clone());
    assert_eq!(client.observer_count_for_test("k"), 1);
    session.subscription.cancel();
    assert_eq!(client.observer_count_for_test("k"), 0);
}
