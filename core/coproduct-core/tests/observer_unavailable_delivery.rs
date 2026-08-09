use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::context::AttributeValue;
use coproduct_core::observer::{FlagValue, TypedFlagObserver};
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

#[derive(Debug, Default)]
struct Sink {
    seen: Mutex<Vec<Vec<(String, Option<FlagValue>)>>>,
}

impl TypedFlagObserver for Sink {
    fn on_transition(&self, _revision: u64, state: &[(String, Option<FlagValue>)]) {
        self.seen.lock().unwrap().push(state.to_vec());
    }
}

#[tokio::test]
async fn clearing_the_snapshot_delivers_unavailable_for_every_observed_key() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag("a", true),
        bool_flag("b", true),
    ]))
    .await;
    let sink = Arc::new(Sink::default());
    let _session = client.observe_keys(vec!["a".to_string(), "b".to_string()], sink.clone());

    // The revoked-key path drops the held snapshot
    client.clear_snapshot_for_test().await;

    let seen = sink.seen.lock().unwrap();
    assert_eq!(seen.len(), 1);
    assert_eq!(
        seen[0],
        vec![("a".to_string(), None), ("b".to_string(), None)]
    );
}

#[tokio::test]
async fn a_key_that_leaves_the_snapshot_delivers_unavailable() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag("kept", true),
        bool_flag("removed", true),
    ]))
    .await;
    let sink = Arc::new(Sink::default());
    let _session = client.observe_keys(
        vec!["kept".to_string(), "removed".to_string()],
        sink.clone(),
    );

    client
        .swap_snapshot_for_test(Arc::new(snapshot_with_flags(vec![bool_flag("kept", true)])))
        .await;

    let seen = sink.seen.lock().unwrap();
    assert_eq!(seen.len(), 1);
    assert_eq!(
        seen[0],
        vec![
            ("kept".to_string(), Some(FlagValue::Bool(true))),
            ("removed".to_string(), None),
        ]
    );
}

/// A BOOL flag whose targeting rule serves a String variation. Under a context
/// that matches the rule the served variation does not match the declared type,
/// so the flag is present but unusable and observation is unavailable. Under any
/// other context it falls through to a usable Bool variation. This is the same
/// declared-type-unusable shape as the `bool_flag_serving_string` fixture, made
/// context-dependent so a pure context change can move a key between usable and
/// unusable
fn bool_flag_unusable_in_us() -> coproduct_core::snapshot::Flag {
    use coproduct_core::snapshot::{
        Condition, Coverage, Flag, FlagType, Operator, Rollout, TargetingRule, Variation,
        VariationValue,
    };
    Flag {
        key: "geo".to_string(),
        r#type: FlagType::Bool,
        enabled: true,
        is_paused: false,
        variations: vec![
            Variation {
                key: "on".to_string(),
                value: VariationValue::Bool(true),
                name: None,
            },
            Variation {
                key: "mistyped".to_string(),
                value: VariationValue::String("not-a-bool".to_string()),
                name: None,
            },
        ],
        off_variation: Some("on".to_string()),
        fallthrough_variation: Some("on".to_string()),
        targeting_rules: vec![TargetingRule {
            rule_id: "33333333-3333-3333-3333-333333333333".to_string(),
            condition: Condition::Attribute {
                attribute: "country".to_string(),
                operator: Operator::Equals,
                values: vec!["US".to_string()],
            },
            coverage: Coverage(10_000),
            rollout: Rollout::Variation {
                variation: "mistyped".to_string(),
            },
            description: None,
        }],
        prerequisites: Vec::new(),
        experiment: None,
    }
}

#[tokio::test]
async fn a_context_change_that_makes_a_key_unusable_delivers_unavailable() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag_unusable_in_us(),
    ]))
    .await;
    client.set_sdk_context_for_test(HashMap::from([(
        "country".to_string(),
        AttributeValue::String("CA".to_string()),
    )]));

    // Outside the rule the flag falls through to a usable Bool, so it seeds usable
    let session = client.observe_key("geo".to_string(), Arc::new(Sink::default()));
    assert_eq!(session.seed[0].1, Some(FlagValue::Bool(true)));

    let sink = Arc::new(Sink::default());
    let _session = client.observe_key("geo".to_string(), sink.clone());

    // The edge now places the user in US, where the rule serves a String on a BOOL
    // flag. Nothing about the snapshot changed: only the context moved the key from
    // usable to unusable
    client
        .swap_sdk_context_for_test(HashMap::from([(
            "country".to_string(),
            AttributeValue::String("US".to_string()),
        )]))
        .await;

    let seen = sink.seen.lock().unwrap();
    assert_eq!(seen.len(), 1);
    assert_eq!(seen[0], vec![("geo".to_string(), None)]);
    // The getter agrees: an unusable projection serves the caller's default
    assert!(!client.get_bool("geo".to_string(), false));
    assert!(client.get_bool("geo".to_string(), true));
}
