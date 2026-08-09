use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

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
async fn snapshot_swap_fires_observer_for_changed_key_only() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "a", false,
        )]))
        .await;

    let rec_a: Arc<Recorder> = Arc::new(Recorder::default());
    let rec_b: Arc<Recorder> = Arc::new(Recorder::default());
    let _sub_a = client.observe_key("a".to_string(), rec_a.clone());
    let _sub_b = client.observe_key("b".to_string(), rec_b.clone());

    let next = snapshot_with_flags(vec![bool_flag("a", true), bool_flag("b", false)]);
    client.swap_snapshot_for_test(Arc::new(next)).await;

    // "a" moved false -> true, so its observer fires with the new value
    let a = rec_a.seen.lock().unwrap();
    assert_eq!(a.len(), 1);
    assert_eq!(a[0], ("a".to_string(), FlagValue::Bool(true)));

    // "b" went absent -> false, which the diff treats as a change and fires
    let b = rec_b.seen.lock().unwrap();
    assert_eq!(b.len(), 1);
    assert_eq!(b[0], ("b".to_string(), FlagValue::Bool(false)));
}
