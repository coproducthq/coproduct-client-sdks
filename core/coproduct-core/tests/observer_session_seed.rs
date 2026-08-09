use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

#[derive(Debug, Default)]
struct Sink {
    seen: Mutex<Vec<(u64, Vec<(String, Option<FlagValue>)>)>>,
}

impl TypedFlagObserver for Sink {
    fn on_transition(&self, revision: u64, state: &[(String, Option<FlagValue>)]) {
        self.seen.lock().unwrap().push((revision, state.to_vec()));
    }
}

#[tokio::test]
async fn a_session_seeds_every_key_with_the_value_its_getter_returns() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "present", true,
        )]))
        .await;

    let session = client.observe_keys(
        vec!["present".to_string(), "absent".to_string()],
        Arc::new(Sink::default()),
    );

    assert_eq!(
        session.seed,
        vec![
            ("present".to_string(), Some(FlagValue::Bool(true))),
            // An unavailable key is present in the seed as None, never omitted,
            // so a bundle seed is a complete map
            ("absent".to_string(), None),
        ]
    );
    assert!(client.get_bool("present".to_string(), false));
}

#[tokio::test]
async fn a_seeded_session_is_not_re_delivered_the_state_it_was_seeded_with() {
    // The lane starts at the registration revision, so a transition that does not
    // move the value delivers nothing and cannot duplicate the seed
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "k", true,
        )]))
        .await;
    let sink = Arc::new(Sink::default());
    let session = client.observe_key("k".to_string(), sink.clone());
    assert_eq!(session.seed[0].1, Some(FlagValue::Bool(true)));

    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("k", true)])))
        .await;
    assert!(sink.seen.lock().unwrap().is_empty());

    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("k", false)])))
        .await;
    let seen = sink.seen.lock().unwrap();
    assert_eq!(seen.len(), 1);
    assert_eq!(
        seen[0].1,
        vec![("k".to_string(), Some(FlagValue::Bool(false)))]
    );
}

#[tokio::test]
async fn a_registration_after_shutdown_is_cancelled_and_seeds_unavailable() {
    let client = CoproductClient::test_instance_with_bool_flag("k", true).await;
    client.shutdown().await;

    let session = client.observe_keys(
        vec!["k".to_string(), "other".to_string()],
        Arc::new(Sink::default()),
    );

    assert!(session.subscription.is_cancelled());
    // Registration does not take a caller default, so the seed is unavailable and
    // the host wrapper resolves it to whatever default the developer supplied
    assert_eq!(
        session.seed,
        vec![("k".to_string(), None), ("other".to_string(), None)]
    );
    assert_eq!(client.observer_count_for_test("k"), 0);
}
