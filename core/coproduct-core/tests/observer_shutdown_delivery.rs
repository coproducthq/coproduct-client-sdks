use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, Weak};

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};

/// Records deliveries and counts its end-of-life closes, so "exactly once" is
/// assertable rather than merely "at least once". It also records whether the
/// coordinator gate was held when it was closed, because ending a subscription
/// must never run under the gate
#[derive(Debug, Default)]
struct ClosingRecorder {
    seen: Mutex<Vec<u64>>,
    closes: AtomicUsize,
    closed_under_gate: AtomicBool,
    client: Mutex<Weak<CoproductClient>>,
}

impl ClosingRecorder {
    fn closes(&self) -> usize {
        self.closes.load(Ordering::SeqCst)
    }
}

impl TypedFlagObserver for ClosingRecorder {
    fn on_transition(&self, revision: u64, _state: &[(String, Option<FlagValue>)]) {
        self.seen.lock().unwrap().push(revision);
    }

    fn on_close(&self) {
        self.closes.fetch_add(1, Ordering::SeqCst);
        // A weak reference, so the observer the registry holds cannot keep the
        // client alive through a cycle
        if let Some(client) = self.client.lock().unwrap().upgrade()
            && client.coordinator_gate_is_held_for_test()
        {
            self.closed_under_gate.store(true, Ordering::SeqCst);
        }
    }
}

fn one(key: &str, value: bool) -> Vec<(String, Option<FlagValue>)> {
    vec![(key.to_string(), Some(FlagValue::Bool(value)))]
}

/// A recorder wired to observe the client that owns it, through a weak reference
fn recorder_for(client: &Arc<CoproductClient>) -> Arc<ClosingRecorder> {
    let recorder = Arc::new(ClosingRecorder::default());
    *recorder.client.lock().unwrap() = Arc::downgrade(client);
    recorder
}

#[tokio::test]
async fn a_delivery_captured_before_shutdown_is_dropped_and_the_session_reports_cancelled() {
    let client = CoproductClient::test_instance_with_bool_flag("k", true).await;
    let recorder = recorder_for(&client);
    let session = client.observe_key("k".to_string(), recorder.clone());
    let id = session.subscription.id();

    // A fanout that is already under way holds clones of the observer and the
    // lane, so removing the registry entry alone would not stop it
    let captured = client
        .capture_for_test(id)
        .expect("the subscription is live before shutdown");

    client.shutdown().await;

    // The adapter was closed explicitly at shutdown, not left waiting on a drop,
    // and not while the coordinator gate was held
    assert_eq!(recorder.closes(), 1, "shutdown closed the adapter");
    assert!(
        !recorder.closed_under_gate.load(Ordering::SeqCst),
        "the adapter was closed under the coordinator gate"
    );
    // The existing cancellation surface reflects shutdown, so a host that asks
    // whether its observation is still live gets the truth
    assert!(session.subscription.is_cancelled());

    captured.deliver(9, one("k", false));
    assert!(
        recorder.seen.lock().unwrap().is_empty(),
        "a delivery captured before shutdown must not reach the observer"
    );
}

#[tokio::test]
async fn cancelling_then_shutting_down_closes_the_adapter_exactly_once() {
    let client = CoproductClient::test_instance_with_bool_flag("k", true).await;
    let recorder = recorder_for(&client);
    let session = client.observe_key("k".to_string(), recorder.clone());

    session.subscription.cancel();
    assert_eq!(recorder.closes(), 1);
    assert!(session.subscription.is_cancelled());

    // Removal is the ownership token, so neither a repeated cancel nor the later
    // shutdown can end the same subscription a second time
    session.subscription.cancel();
    client.shutdown().await;
    assert_eq!(
        recorder.closes(),
        1,
        "the adapter was closed more than once"
    );
    assert!(!recorder.closed_under_gate.load(Ordering::SeqCst));
    assert_eq!(client.observer_count_for_test("k"), 0);
}

#[tokio::test]
async fn shutting_down_then_cancelling_also_closes_exactly_once() {
    // The other order of the same race. Shutdown takes the entry, so the cancel
    // that follows finds nothing to end rather than closing a second time
    let client = CoproductClient::test_instance_with_bool_flag("k", true).await;
    let recorder = recorder_for(&client);
    let session = client.observe_key("k".to_string(), recorder.clone());

    client.shutdown().await;
    assert_eq!(recorder.closes(), 1);
    assert!(session.subscription.is_cancelled());

    session.subscription.cancel();
    assert_eq!(
        recorder.closes(),
        1,
        "the adapter was closed more than once"
    );
    assert!(!recorder.closed_under_gate.load(Ordering::SeqCst));
}

#[tokio::test]
async fn concurrent_cancel_and_shutdown_close_exactly_once() {
    // The interleaving itself. Whichever side removes the entry ends it, so
    // running both concurrently across many attempts must never double-close and
    // never leave an adapter open
    for _ in 0..50 {
        let client = CoproductClient::test_instance_with_bool_flag("k", true).await;
        let recorder = recorder_for(&client);
        let session = client.observe_key("k".to_string(), recorder.clone());
        let subscription = session.subscription.clone();

        let canceller = std::thread::spawn(move || subscription.cancel());
        client.shutdown().await;
        canceller.join().unwrap();

        assert_eq!(
            recorder.closes(),
            1,
            "exactly one side ended the subscription"
        );
        assert!(session.subscription.is_cancelled());
    }
}
