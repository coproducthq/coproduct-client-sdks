use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::evaluation_event::{EvaluationEvent, EvaluationListener, EvaluationReason};
use coproduct_core::hooks::FlagType;

#[derive(Debug, Default)]
struct Capture {
    events: Mutex<Vec<EvaluationEvent>>,
}

impl EvaluationListener for Capture {
    fn on_evaluation(&self, event: &EvaluationEvent) {
        self.events.lock().unwrap().push(event.clone());
    }
}

#[tokio::test]
async fn get_bool_emits_an_evaluation_event() {
    let client = CoproductClient::test_instance_with_bool_flag("show-banner", true).await;
    let cap: Arc<Capture> = Arc::new(Capture::default());
    client.set_evaluation_listener_for_test(cap.clone()).await;

    let _ = client.get_bool("show-banner".to_string(), false);

    let events = cap.events.lock().unwrap().clone();
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    assert_eq!(ev.flag_key, "show-banner");
    assert_eq!(ev.flag_type, FlagType::Bool);
    // The test flag carries no targeting rules, so the pipeline resolves it via
    // the fallthrough variation rather than a rule match
    assert_eq!(ev.reason, EvaluationReason::Fallthrough);
    assert!(ev.error_code.is_none());
}

#[tokio::test]
async fn missing_flag_emits_event_with_error_code() {
    let client = CoproductClient::test_instance_with_bool_flag("known", true).await;
    let cap: Arc<Capture> = Arc::new(Capture::default());
    client.set_evaluation_listener_for_test(cap.clone()).await;

    let _ = client.get_bool("unknown".to_string(), false);

    let events = cap.events.lock().unwrap().clone();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].reason, EvaluationReason::Error);
    assert!(events[0].error_code.is_some());
}
