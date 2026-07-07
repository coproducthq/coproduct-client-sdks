use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::context::AttributeValue;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};
use coproduct_core::snapshot::{Condition, Coverage, Operator, Rollout, TargetingRule};

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

// Flag that turns on only when the server-derived `country` attribute is US, so
// resolving it correctly requires the SDK context layer
fn country_us_flag() -> coproduct_core::snapshot::Flag {
    let mut flag = bool_flag("geo", false);
    flag.targeting_rules = vec![TargetingRule {
        rule_id: "11111111-1111-1111-1111-111111111111".to_string(),
        condition: Condition::Attribute {
            attribute: "country".to_string(),
            operator: Operator::Equals,
            values: vec!["US".to_string()],
        },
        coverage: Coverage(10_000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    }];
    flag
}

// The observer fanout must evaluate with the server-derived SDK context layer,
// exactly as the typed getters do. Otherwise an observed value would disagree
// with `get_bool` for a flag whose targeting references an edge attribute.
#[tokio::test]
async fn fanout_delivers_the_sdk_context_aware_value() {
    // Start with the flag plain-off, then set the SDK context so country is US
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "geo", false,
        )]))
        .await;
    client.set_sdk_context_for_test(HashMap::from([(
        "country".to_string(),
        AttributeValue::String("US".to_string()),
    )]));

    let recorder: Arc<Recorder> = Arc::new(Recorder::default());
    let _sub = client.observe_key("geo".to_string(), recorder.clone());

    // Swap in the country-targeted flag. With country US in the SDK context the
    // rule matches, so the getter resolves true and the fanout must deliver the
    // same true. Without the SDK context the rule would miss, the value would
    // stay false, and the observer would never fire
    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![country_us_flag()])))
        .await;

    assert!(
        client.get_bool("geo".to_string(), false),
        "the getter resolves the country rule via the SDK context"
    );
    let seen = recorder.seen.lock().unwrap();
    assert_eq!(
        seen.len(),
        1,
        "the observer fires once for the changed value"
    );
    assert_eq!(
        seen[0],
        FlagValue::Bool(true),
        "the fanout delivers the SDK-context-aware value, matching get_bool"
    );
}

// A poll can leave a flag's definition unchanged while the edge-derived SDK
// context moves (the user's geo shifts). The swap fanout must diff against the
// context observers last saw, so a value that changes only because the SDK context
// changed still notifies observers.
#[tokio::test]
async fn fanout_notifies_on_an_sdk_context_change_that_moves_the_value() {
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![country_us_flag()]))
            .await;
    client.set_sdk_context_for_test(HashMap::from([(
        "country".to_string(),
        AttributeValue::String("US".to_string()),
    )]));
    // Under US the country rule matches and the flag is on
    assert!(client.get_bool("geo".to_string(), false));

    let recorder: Arc<Recorder> = Arc::new(Recorder::default());
    let _sub = client.observe_key("geo".to_string(), recorder.clone());

    // Same snapshot, but the edge now places the user in CA. The value drops to
    // off, and the observer must hear it even though only the SDK context changed
    client
        .swap_sdk_context_for_test(HashMap::from([(
            "country".to_string(),
            AttributeValue::String("CA".to_string()),
        )]))
        .await;

    assert!(
        !client.get_bool("geo".to_string(), false),
        "the getter now misses the country rule"
    );
    let seen = recorder.seen.lock().unwrap();
    assert_eq!(
        seen.len(),
        1,
        "the observer fires on the sdk-context-driven change"
    );
    assert_eq!(seen[0], FlagValue::Bool(false));
}
