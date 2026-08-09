use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use coproduct_core::client::CoproductClient;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};
use coproduct_core::snapshot::{Condition, Coverage, Operator, Rollout, TargetingRule};

/// A flag that is off for an anonymous identity and on for `user-1`. Targeting on
/// `user_id` resolves through the targeting key, so `identify` alone moves this
/// flag's value, which is what makes a reentrant `identify` produce a second
/// delivery on the same subscription's lane
fn identity_gate() -> coproduct_core::snapshot::Flag {
    let mut flag = bool_flag("gate", false);
    flag.targeting_rules = vec![TargetingRule {
        rule_id: "44444444-4444-4444-4444-444444444444".to_string(),
        condition: Condition::Attribute {
            attribute: "user_id".to_string(),
            operator: Operator::Equals,
            values: vec!["user-1".to_string()],
        },
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    }];
    flag
}

/// Stands in for an adapter channel: `on_transition` records and returns, and the
/// host drains afterwards, off the delivery lane
#[derive(Debug, Default)]
struct Channel {
    queued: Mutex<Vec<Vec<(String, Option<FlagValue>)>>>,
}

impl Channel {
    fn drain(&self) -> Vec<Vec<(String, Option<FlagValue>)>> {
        std::mem::take(&mut *self.queued.lock().unwrap())
    }
}

impl TypedFlagObserver for Channel {
    fn on_transition(&self, _revision: u64, state: &[(String, Option<FlagValue>)]) {
        self.queued.lock().unwrap().push(state.to_vec());
    }
}

#[tokio::test]
async fn a_drained_callback_may_re_enter_the_sdk_without_deadlocking() {
    // Start with no snapshot, so installing the gate is itself a transition that
    // delivers (unavailable -> available) and gives the host something to drain
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![])).await;
    let channel = Arc::new(Channel::default());
    let session = client.observe_key("gate".to_string(), channel.clone());
    assert_eq!(
        session.seed[0].1, None,
        "the gate is not in the snapshot yet"
    );

    // Bound the whole sequence: under a design that held the lane across an awaited
    // host callback, the identify below would never complete
    tokio::time::timeout(Duration::from_secs(5), async {
        client
            .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![identity_gate()])))
            .await;

        // The host drains what the delivery enqueued and, from that drained
        // callback, re-enters the SDK. The gate is targeted on identity, so this
        // identify is itself an accepted transition that changes the observed
        // value and therefore fans out to this same subscription's lane. That
        // reacquisition is the deadlock the synchronous enqueue design prevents
        let delivered = channel.drain();
        assert_eq!(delivered.len(), 1);
        assert_eq!(
            delivered[0],
            vec![("gate".to_string(), Some(FlagValue::Bool(false)))],
            "anonymous identity misses the targeting rule"
        );

        client
            .identify("user-1".to_string(), HashMap::new(), false)
            .await
            .expect("identify succeeds");
    })
    .await
    .expect("re-entering the SDK from a drained delivery does not deadlock");

    // The reentrant identify produced its own delivery on the same lane
    let after = channel.drain();
    assert_eq!(
        after.len(),
        1,
        "identify delivered on the same subscription"
    );
    assert_eq!(
        after[0],
        vec![("gate".to_string(), Some(FlagValue::Bool(true)))]
    );
    assert_eq!(client.targeting_key_for_test(), "user-1");
    assert!(
        client.get_bool("gate".to_string(), false),
        "the delivered value equals the getter for the same transition"
    );
}
