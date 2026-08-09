use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

/// Records the revisions it was handed and can block inside one chosen
/// revision's callback. `entered` is signaled before blocking, so a test can
/// prove a later delivery has not entered rather than inferring it from a sleep
#[derive(Debug)]
struct GatedRecorder {
    entered: Sender<u64>,
    release: Mutex<Receiver<()>>,
    block_revision: AtomicU64,
    seen: Mutex<Vec<(u64, Vec<(String, Option<FlagValue>)>)>>,
}

impl TypedFlagObserver for GatedRecorder {
    fn on_transition(&self, revision: u64, state: &[(String, Option<FlagValue>)]) {
        self.entered.send(revision).expect("test receiver is live");
        if revision == self.block_revision.load(Ordering::SeqCst) {
            self.release
                .lock()
                .unwrap()
                .recv()
                .expect("test releases the blocked callback");
        }
        self.seen.lock().unwrap().push((revision, state.to_vec()));
    }
}

fn one(key: &str, value: bool) -> Vec<(String, Option<FlagValue>)> {
    vec![(key.to_string(), Some(FlagValue::Bool(value)))]
}

#[tokio::test]
async fn a_newer_delivery_waits_for_an_older_callback_to_finish() {
    let client = CoproductClient::test_instance_with_bool_flag("k", true).await;
    let (entered_tx, entered_rx) = channel();
    let (release_tx, release_rx) = channel();
    let recorder = Arc::new(GatedRecorder {
        entered: entered_tx,
        release: Mutex::new(release_rx),
        block_revision: AtomicU64::new(6),
        seen: Mutex::new(Vec::new()),
    });
    // Bind the session for the whole test. Reading the id off a temporary would
    // drop the session at the semicolon, cancelling the subscription before a
    // single delivery could reach it
    let session = client.observe_key("k".to_string(), recorder.clone());
    let id = session.subscription.id();

    let older = {
        let client = client.clone();
        thread::spawn(move || client.deliver_for_test(id, 6, one("k", false)))
    };
    // Revision 6's callback has entered and is now blocked holding the lane
    assert_eq!(entered_rx.recv().unwrap(), 6);

    let (attempting_tx, attempting_rx) = channel();
    let newer = {
        let client = client.clone();
        thread::spawn(move || {
            // Announce that this thread is scheduled and about to take the lane,
            // so a silent revision 8 below means blocked rather than unscheduled
            attempting_tx.send(()).unwrap();
            client.deliver_for_test(id, 8, one("k", true))
        })
    };
    attempting_rx.recv().unwrap();
    // Nothing arrives from revision 8 while 6 holds the lane
    thread::sleep(Duration::from_millis(50));
    assert!(
        entered_rx.try_recv().is_err(),
        "a newer delivery entered while an older callback was still running"
    );

    release_tx.send(()).unwrap();
    older.join().unwrap();
    newer.join().unwrap();

    let seen = recorder.seen.lock().unwrap();
    let revisions: Vec<u64> = seen.iter().map(|(revision, _)| *revision).collect();
    assert_eq!(revisions, vec![6, 8], "deliveries run in revision order");
}

#[tokio::test]
async fn a_stale_revision_is_discarded() {
    let client = CoproductClient::test_instance_with_bool_flag("k", true).await;
    let (entered_tx, _entered_rx) = channel();
    let (_release_tx, release_rx) = channel();
    let recorder = Arc::new(GatedRecorder {
        entered: entered_tx,
        release: Mutex::new(release_rx),
        // Nothing blocks: 0 is never a delivered revision
        block_revision: AtomicU64::new(0),
        seen: Mutex::new(Vec::new()),
    });
    let session = client.observe_key("k".to_string(), recorder.clone());
    let id = session.subscription.id();

    client.deliver_for_test(id, 8, one("k", true));
    client.deliver_for_test(id, 6, one("k", false));

    let seen = recorder.seen.lock().unwrap();
    assert_eq!(seen.len(), 1, "the older revision was discarded");
    assert_eq!(seen[0].0, 8);
    assert_eq!(seen[0].1, one("k", true));
}

#[tokio::test]
async fn a_stale_batch_arriving_late_cannot_undo_a_newer_full_state() {
    // The property full-state batching exists for: a newer batch arrives first and
    // an older one arrives after, and the older one is dropped without losing the
    // key it was the only batch to change. The newer batch is produced by the REAL
    // fanout, so its completeness is the production shape rather than a hand-built
    // vector, and only the stale arrival is injected
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag("a", false),
        bool_flag("b", false),
    ]))
    .await;
    let (entered_tx, _entered_rx) = channel();
    let (_release_tx, release_rx) = channel();
    let recorder = Arc::new(GatedRecorder {
        entered: entered_tx,
        release: Mutex::new(release_rx),
        block_revision: AtomicU64::new(0),
        seen: Mutex::new(Vec::new()),
    });
    let session = client.observe_keys(vec!["a".to_string(), "b".to_string()], recorder.clone());
    let id = session.subscription.id();

    // One real transition moves both keys, so the lane has applied its revision
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![
            bool_flag("a", true),
            bool_flag("b", true),
        ])))
        .await;
    let applied = recorder.seen.lock().unwrap()[0].0;

    // A batch from an earlier revision now arrives late, carrying the state before
    // either key moved. It must be dropped rather than rewinding the observation
    client.deliver_for_test(
        id,
        applied - 1,
        vec![
            ("a".to_string(), Some(FlagValue::Bool(false))),
            ("b".to_string(), Some(FlagValue::Bool(false))),
        ],
    );

    let seen = recorder.seen.lock().unwrap();
    assert_eq!(seen.len(), 1, "the stale batch was discarded");
    assert_eq!(
        seen[0].1,
        vec![
            ("a".to_string(), Some(FlagValue::Bool(true))),
            ("b".to_string(), Some(FlagValue::Bool(true))),
        ],
        "the observation retains the newer complete state for every key"
    );
}

#[tokio::test]
async fn every_batch_carries_the_keys_this_transition_did_not_change() {
    // Two real transitions, each changing a different key of one two-key
    // subscription. Because each batch is the subscription's complete state, the
    // second delivery still carries the first transition's key at its new value,
    // which is what makes dropping a stale batch safe
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag("a", false),
        bool_flag("b", false),
    ]))
    .await;
    let (entered_tx, _entered_rx) = channel();
    let (_release_tx, release_rx) = channel();
    let recorder = Arc::new(GatedRecorder {
        entered: entered_tx,
        release: Mutex::new(release_rx),
        block_revision: AtomicU64::new(0),
        seen: Mutex::new(Vec::new()),
    });
    let _session = client.observe_keys(vec!["a".to_string(), "b".to_string()], recorder.clone());

    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![
            bool_flag("a", true),
            bool_flag("b", false),
        ])))
        .await;
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![
            bool_flag("a", true),
            bool_flag("b", true),
        ])))
        .await;

    let seen = recorder.seen.lock().unwrap();
    assert_eq!(seen.len(), 2);
    assert!(
        seen[0].0 < seen[1].0,
        "revisions increase across transitions"
    );
    assert_eq!(
        seen[1].1,
        vec![
            ("a".to_string(), Some(FlagValue::Bool(true))),
            ("b".to_string(), Some(FlagValue::Bool(true))),
        ],
        "the later batch carries the earlier transition's key too"
    );
}

#[tokio::test]
async fn a_subscription_cancelled_before_a_transition_receives_nothing() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "k", false,
        )]))
        .await;
    let (entered_tx, _entered_rx) = channel();
    let (_release_tx, release_rx) = channel();
    let recorder = Arc::new(GatedRecorder {
        entered: entered_tx,
        release: Mutex::new(release_rx),
        block_revision: AtomicU64::new(0),
        seen: Mutex::new(Vec::new()),
    });
    // The live recorder needs its own retained channel pair. Halves from two
    // throwaway channels would leave the receiver dropped, and the recorder's
    // send would panic during the fanout
    let (live_entered_tx, _live_entered_rx) = channel();
    let (_live_release_tx, live_release_rx) = channel();
    let live = Arc::new(GatedRecorder {
        entered: live_entered_tx,
        release: Mutex::new(live_release_rx),
        block_revision: AtomicU64::new(0),
        seen: Mutex::new(Vec::new()),
    });
    let cancelled = client.observe_key("k".to_string(), recorder.clone());
    let _still_live = client.observe_key("k".to_string(), live.clone());

    cancelled.subscription.cancel();
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("k", true)])))
        .await;

    // The still-live observation proves the transition really fanned out, so the
    // cancelled one's silence is cancellation rather than a missing transition
    assert_eq!(live.seen.lock().unwrap().len(), 1);
    assert!(recorder.seen.lock().unwrap().is_empty());
}
