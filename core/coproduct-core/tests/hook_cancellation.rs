use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient;
use coproduct_core::hooks::{EvaluationHook, EvaluationStage, HookContext};

/// Counts every stage invocation so a test can assert whether a getter call
/// reached the hook after the handle was unregistered
#[derive(Debug, Default)]
struct Trace {
    seen: Mutex<u32>,
}

impl EvaluationHook for Trace {
    fn on_stage(&self, _stage: EvaluationStage, _ctx: &HookContext) {
        *self.seen.lock().unwrap() += 1;
    }
}

#[tokio::test]
async fn dropped_handle_unregisters_hook() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;
    let trace = Arc::new(Trace::default());

    {
        let _handle = client.add_evaluation_hook(trace.clone());
    }

    let _ = client.get_bool("f".to_string(), false);

    assert_eq!(*trace.seen.lock().unwrap(), 0);
}

#[tokio::test]
async fn explicit_cancel_unregisters_hook() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;
    let trace = Arc::new(Trace::default());
    let handle = client.add_evaluation_hook(trace.clone());

    handle.cancel();
    assert!(handle.is_cancelled());

    let _ = client.get_bool("f".to_string(), false);

    assert_eq!(*trace.seen.lock().unwrap(), 0);
}

#[tokio::test]
async fn double_cancel_is_safe() {
    let client = CoproductClient::test_instance_with_bool_flag("f", true).await;
    let trace = Arc::new(Trace::default());
    let handle = client.add_evaluation_hook(trace.clone());

    handle.cancel();
    handle.cancel();
    assert!(handle.is_cancelled());

    let _ = client.get_bool("f".to_string(), false);

    assert_eq!(*trace.seen.lock().unwrap(), 0);
}
