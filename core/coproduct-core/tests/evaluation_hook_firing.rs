use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::hooks::{EvaluationHook, EvaluationStage, HookContext};

/// Records every stage and flag key it observes so a test can assert the firing
/// order around a single getter call
#[derive(Debug, Default)]
struct Trace {
    seen: Mutex<Vec<(EvaluationStage, String)>>,
}

impl EvaluationHook for Trace {
    fn on_stage(&self, stage: EvaluationStage, ctx: &HookContext) {
        self.seen
            .lock()
            .unwrap()
            .push((stage, ctx.flag_key().to_string()));
    }
}

#[tokio::test]
async fn success_fires_before_after_finally() {
    let client = CoproductClient::test_instance_with_bool_flag("flag", true).await;
    let trace = Arc::new(Trace::default());
    let _handle = client.add_evaluation_hook(trace.clone());

    let value = client.get_bool("flag".to_string(), false);
    assert!(value);

    let seen = trace.seen.lock().unwrap().clone();
    assert_eq!(
        seen,
        vec![
            (EvaluationStage::Before, "flag".to_string()),
            (EvaluationStage::After, "flag".to_string()),
            (EvaluationStage::Finally, "flag".to_string()),
        ]
    );
}

#[tokio::test]
async fn missing_flag_fires_before_error_finally() {
    let client = CoproductClient::test_instance_with_bool_flag("present", true).await;
    let trace = Arc::new(Trace::default());
    let _handle = client.add_evaluation_hook(trace.clone());

    let value = client.get_bool("absent".to_string(), false);
    assert!(!value);

    let seen = trace.seen.lock().unwrap().clone();
    assert_eq!(
        seen,
        vec![
            (EvaluationStage::Before, "absent".to_string()),
            (EvaluationStage::Error, "absent".to_string()),
            (EvaluationStage::Finally, "absent".to_string()),
        ]
    );
}

#[tokio::test]
async fn dropping_the_handle_unregisters_the_hook() {
    let client = CoproductClient::test_instance_with_bool_flag("flag", true).await;
    let trace = Arc::new(Trace::default());
    let handle = client.add_evaluation_hook(trace.clone());

    drop(handle);

    let _ = client.get_bool("flag".to_string(), false);

    assert!(trace.seen.lock().unwrap().is_empty());
}
