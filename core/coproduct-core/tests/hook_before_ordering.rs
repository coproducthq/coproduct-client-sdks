use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::hooks::{EvaluationHook, EvaluationStage, HookContext};

/// Records the stage and whether the context already carries a resolved value at
/// each stage. This pins the bracket contract: `Before` runs with an unevaluated
/// context that has no resolved value yet, while the terminal stages see the
/// resolved value after the pipeline runs
#[derive(Debug, Default)]
struct RecordingHook {
    log: Mutex<Vec<(EvaluationStage, bool)>>,
}

impl EvaluationHook for RecordingHook {
    fn on_stage(&self, stage: EvaluationStage, ctx: &HookContext) {
        self.log
            .lock()
            .unwrap()
            .push((stage, ctx.value().is_some()));
    }
}

#[tokio::test]
async fn before_runs_with_unevaluated_context_on_success() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;
    let hook = Arc::new(RecordingHook::default());
    let _handle = client.add_evaluation_hook(hook.clone());

    let _ = client.get_bool("f".to_string(), false);

    let log = hook.log.lock().unwrap().clone();
    assert_eq!(
        log,
        vec![
            (EvaluationStage::Before, false),
            (EvaluationStage::After, true),
            (EvaluationStage::Finally, true),
        ]
    );
}

#[tokio::test]
async fn before_runs_with_unevaluated_context_on_error() {
    let client = CoproductClient::test_instance_with_bool_flag("present", true).await;
    let hook = Arc::new(RecordingHook::default());
    let _handle = client.add_evaluation_hook(hook.clone());

    // A missing flag drives the error path, which still enriches the context with
    // the default value before the Error and Finally stages
    let _ = client.get_bool("absent".to_string(), false);

    let log = hook.log.lock().unwrap().clone();
    assert_eq!(
        log,
        vec![
            (EvaluationStage::Before, false),
            (EvaluationStage::Error, true),
            (EvaluationStage::Finally, true),
        ]
    );
}
