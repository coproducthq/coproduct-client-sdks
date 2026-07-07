use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::evaluation_event::{EvaluationEvent, EvaluationListener, EvaluationReason};
use coproduct_core::snapshot::test_support::snapshot_with_flags;
use coproduct_core::snapshot::{Flag, FlagType, Variation, VariationValue};

// The plain getters serve the caller default on a pipeline error or a projection
// shape mismatch, and their analytics event must report that as an error rather
// than a targeting match that never delivered its variant. This keeps get_bool
// and get_bool_details emitting the same event for the same evaluation.

#[derive(Debug, Default)]
struct Capture {
    events: Mutex<Vec<EvaluationEvent>>,
}

impl EvaluationListener for Capture {
    fn on_evaluation(&self, event: &EvaluationEvent) {
        self.events.lock().unwrap().push(event.clone());
    }
}

// A BOOL-typed flag whose served (fallthrough) variation holds a String value.
// Tolerant ingestion keeps such a flag, so the pipeline resolves the variation
// but the bool projection fails and the default is served
fn bool_flag_serving_string(key: &str) -> Flag {
    Flag {
        key: key.to_string(),
        r#type: FlagType::Bool,
        enabled: true,
        is_paused: false,
        variations: vec![Variation {
            key: "on".to_string(),
            value: VariationValue::String("not-a-bool".to_string()),
            name: None,
        }],
        off_variation: Some("on".to_string()),
        fallthrough_variation: Some("on".to_string()),
        targeting_rules: Vec::new(),
        prerequisites: Vec::new(),
        experiment: None,
    }
}

// A BOOL flag with a null fallthrough variation. Reaching the fallthrough with no
// variation to serve trips RULE_CIRCUIT_BREAK and resolves to the off variation
fn circuit_break_flag(key: &str) -> Flag {
    Flag {
        key: key.to_string(),
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
                key: "off".to_string(),
                value: VariationValue::Bool(false),
                name: None,
            },
        ],
        off_variation: Some("off".to_string()),
        fallthrough_variation: None,
        targeting_rules: Vec::new(),
        prerequisites: Vec::new(),
        experiment: None,
    }
}

#[tokio::test]
async fn wrong_typed_variation_emits_type_mismatch_not_targeting_match() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        bool_flag_serving_string("mistyped"),
    ]))
    .await;
    let cap: Arc<Capture> = Arc::new(Capture::default());
    client.set_evaluation_listener_for_test(cap.clone()).await;

    // The served variation is a String, so the bool getter serves the default
    let value = client.get_bool("mistyped".to_string(), false);
    assert!(!value, "a shape mismatch serves the caller default");

    let events = cap.events.lock().unwrap().clone();
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    assert_eq!(
        ev.reason,
        EvaluationReason::Error,
        "a served-default projection failure reports an error, not a match"
    );
    assert_eq!(ev.error_code, Some(EvaluationErrorCode::TypeMismatch));
    assert_eq!(
        ev.variant, None,
        "no variant is claimed when the default was served"
    );
}

#[tokio::test]
async fn plain_and_detail_getters_agree_on_circuit_break_event() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        circuit_break_flag("broken"),
    ]))
    .await;
    let cap: Arc<Capture> = Arc::new(Capture::default());
    client.set_evaluation_listener_for_test(cap.clone()).await;

    let _ = client.get_bool("broken".to_string(), false);
    let _ = client.get_bool_details("broken".to_string(), false);

    let events = cap.events.lock().unwrap().clone();
    assert_eq!(events.len(), 2, "both getters emit an event");
    let plain = &events[0];
    let detail = &events[1];

    assert_eq!(plain.reason, EvaluationReason::Error);
    assert_eq!(plain.variant, None);
    assert_eq!(
        plain.error_code,
        Some(EvaluationErrorCode::RuleCircuitBreak)
    );

    // The two getter flavors must emit the same variant, reason, and error code
    // for the same evaluation
    assert_eq!(plain.reason, detail.reason);
    assert_eq!(plain.variant, detail.variant);
    assert_eq!(plain.error_code, detail.error_code);
}
