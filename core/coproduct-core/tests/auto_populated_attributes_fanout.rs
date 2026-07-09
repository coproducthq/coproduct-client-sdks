use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::context::AttributeValue;
use coproduct_core::events::{LifecycleEvent, LifecycleHandler};
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};
use coproduct_core::snapshot::{Condition, Coverage, Operator, Rollout, TargetingRule};

#[derive(Debug, Default)]
struct EventSink {
    events: Mutex<Vec<LifecycleEvent>>,
}

#[async_trait::async_trait]
impl LifecycleHandler for EventSink {
    async fn on_event(&self, e: LifecycleEvent) {
        self.events.lock().unwrap().push(e);
    }
}

#[derive(Debug, Default)]
struct Recorder {
    seen: Mutex<Vec<FlagValue>>,
}

#[async_trait::async_trait]
impl TypedFlagObserver for Recorder {
    async fn on_change(&self, _key: &str, value: &FlagValue) {
        self.seen.lock().unwrap().push(value.clone());
    }
}

// Flag that turns on only on wifi, so resolving it requires the auto-populated
// network_type the platform wrapper pushes
fn wifi_flag() -> coproduct_core::snapshot::Flag {
    let mut flag = bool_flag("wifi-only", false);
    flag.targeting_rules = vec![TargetingRule {
        rule_id: "22222222-2222-2222-2222-222222222222".to_string(),
        condition: Condition::Attribute {
            attribute: "network_type".to_string(),
            operator: Operator::Equals,
            values: vec!["wifi".to_string()],
        },
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    }];
    flag
}

// A live network_type change must re-evaluate and re-emit like an identity or
// sdkContext change, and a value-preserving upsert must stay silent
#[tokio::test]
async fn auto_populated_upsert_notifies_observers_and_noop_stays_silent() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![wifi_flag()])).await;
    assert!(
        !client.get_bool("wifi-only".to_string(), false),
        "no network_type yet, the rule falls through"
    );

    let recorder: Arc<Recorder> = Arc::new(Recorder::default());
    let _sub = client.observe_key("wifi-only".to_string(), recorder.clone());

    client
        .set_auto_populated_attributes(HashMap::from([(
            "network_type".to_string(),
            AttributeValue::String("wifi".to_string()),
        )]))
        .await;

    assert!(client.get_bool("wifi-only".to_string(), false));
    assert_eq!(
        recorder.seen.lock().unwrap().as_slice(),
        &[FlagValue::Bool(true)],
        "the observer hears the value move when the auto layer changes"
    );

    // Same value again: nothing moved, so the fanout diff delivers nothing
    client
        .set_auto_populated_attributes(HashMap::from([(
            "network_type".to_string(),
            AttributeValue::String("wifi".to_string()),
        )]))
        .await;
    assert_eq!(
        recorder.seen.lock().unwrap().len(),
        1,
        "a value-preserving upsert does not re-notify"
    );
}

// Machine-initiated upserts repeat, so a no-op must not surface as a context
// change to app lifecycle handlers: only a real layer change fires events.
// This deliberately diverges from the developer identity mutators, whose
// explicit calls keep their unconditional event contract
#[tokio::test]
async fn noop_and_rejected_upserts_emit_no_lifecycle_events() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![wifi_flag()])).await;
    let sink: Arc<EventSink> = Arc::new(EventSink::default());
    let on_reconciling = client.add_handler(LifecycleEvent::Reconciling, sink.clone());
    let on_context_changed = client.add_handler(LifecycleEvent::ContextChanged, sink.clone());

    // Rejected names only: nothing was accepted, nothing fires
    client
        .set_auto_populated_attributes(HashMap::from([(
            "plan".to_string(),
            AttributeValue::String("pro".to_string()),
        )]))
        .await;
    assert!(sink.events.lock().unwrap().is_empty());

    // A real change fires reconciling then context changed, like the identity
    // mutators
    client
        .set_auto_populated_attributes(HashMap::from([(
            "network_type".to_string(),
            AttributeValue::String("wifi".to_string()),
        )]))
        .await;
    assert_eq!(
        sink.events.lock().unwrap().as_slice(),
        &[LifecycleEvent::Reconciling, LifecycleEvent::ContextChanged]
    );

    // The same value again is a no-op and stays silent
    client
        .set_auto_populated_attributes(HashMap::from([(
            "network_type".to_string(),
            AttributeValue::String("wifi".to_string()),
        )]))
        .await;
    assert_eq!(sink.events.lock().unwrap().len(), 2);

    on_reconciling.cancel();
    on_context_changed.cancel();
}
