use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::hooks::{EvaluationHook, HookContext, HookOutcome, HookRegistry};
use coproduct_core::pipeline::{RequestedType, evaluate};
use coproduct_core::snapshot::test_support::{bool_flag_with_prereqs, snapshot_with_flags};
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct RecordingHook {
    calls: Mutex<Vec<String>>,
}

impl EvaluationHook for RecordingHook {
    fn before(&self, ctx: &HookContext<'_>) -> HookOutcome {
        self.calls
            .lock()
            .unwrap()
            .push(format!("before:{}", ctx.flag_key));
        HookOutcome::Proceed
    }
    fn after(&self, ctx: &HookContext<'_>, variant: &str) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("after:{}:{}", ctx.flag_key, variant));
    }
    fn error(&self, ctx: &HookContext<'_>, code: EvaluationErrorCode, _msg: &str) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("error:{}:{:?}", ctx.flag_key, code));
    }
    fn finally(&self, ctx: &HookContext<'_>) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("finally:{}", ctx.flag_key));
    }
}

#[test]
fn happy_path_fires_before_after_finally_in_order() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("plain-flag", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let hook = Arc::new(RecordingHook::default());
    let mut registry = HookRegistry::default();
    registry.add(hook.clone());

    let _ = evaluate(
        Some(&snapshot),
        "plain-flag",
        RequestedType::Bool,
        &ctx,
        &registry,
    );

    let calls = hook.calls.lock().unwrap().clone();
    assert_eq!(
        calls,
        vec![
            "before:plain-flag".to_string(),
            "after:plain-flag:on".to_string(),
            "finally:plain-flag".to_string(),
        ]
    );
}

#[test]
fn circuit_break_fires_before_error_finally() {
    let mut flag = bool_flag_with_prereqs("no-fallthrough", &[]);
    flag.fallthrough_variation = None;
    let snapshot = snapshot_with_flags(vec![flag]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let hook = Arc::new(RecordingHook::default());
    let mut registry = HookRegistry::default();
    registry.add(hook.clone());

    let _ = evaluate(
        Some(&snapshot),
        "no-fallthrough",
        RequestedType::Bool,
        &ctx,
        &registry,
    );

    let calls = hook.calls.lock().unwrap().clone();
    assert_eq!(calls.len(), 3);
    assert_eq!(calls[0], "before:no-fallthrough");
    assert!(calls[1].starts_with("error:no-fallthrough:RuleCircuitBreak"));
    assert_eq!(calls[2], "finally:no-fallthrough");
}

#[test]
fn prereq_recursion_fires_inner_hooks_per_descent() {
    let snapshot = snapshot_with_flags(vec![
        bool_flag_with_prereqs("dependent", &[("gate", "on")]),
        bool_flag_with_prereqs("gate", &[]),
    ]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let hook = Arc::new(RecordingHook::default());
    let mut registry = HookRegistry::default();
    registry.add(hook.clone());

    let _ = evaluate(
        Some(&snapshot),
        "dependent",
        RequestedType::Bool,
        &ctx,
        &registry,
    );

    let calls = hook.calls.lock().unwrap().clone();
    let outer_before = calls.iter().position(|c| c == "before:dependent").unwrap();
    let inner_finally = calls.iter().position(|c| c == "finally:gate").unwrap();
    let outer_after = calls
        .iter()
        .position(|c| c == "after:dependent:on")
        .unwrap();
    assert!(outer_before < inner_finally && inner_finally < outer_after);
}

#[test]
fn no_snapshot_fires_before_error_finally() {
    let ctx = EvaluationContext::with_targeting_key("u1");
    let hook = Arc::new(RecordingHook::default());
    let mut registry = HookRegistry::default();
    registry.add(hook.clone());

    let _ = evaluate(None, "any-flag", RequestedType::Bool, &ctx, &registry);

    let calls = hook.calls.lock().unwrap().clone();
    assert_eq!(calls.len(), 3);
    assert_eq!(calls[0], "before:any-flag");
    assert!(calls[1].starts_with("error:any-flag:ProviderNotReady"));
    assert_eq!(calls[2], "finally:any-flag");
}

#[test]
fn missing_flag_fires_before_error_finally() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("real-flag", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let hook = Arc::new(RecordingHook::default());
    let mut registry = HookRegistry::default();
    registry.add(hook.clone());

    let _ = evaluate(
        Some(&snapshot),
        "ghost-flag",
        RequestedType::Bool,
        &ctx,
        &registry,
    );

    let calls = hook.calls.lock().unwrap().clone();
    assert_eq!(calls.len(), 3);
    assert_eq!(calls[0], "before:ghost-flag");
    assert!(calls[1].starts_with("error:ghost-flag:FlagNotFound"));
    assert_eq!(calls[2], "finally:ghost-flag");
}

#[test]
fn type_mismatch_fires_before_error_finally() {
    let snapshot = snapshot_with_flags(vec![bool_flag_with_prereqs("bool-flag", &[])]);
    let ctx = EvaluationContext::with_targeting_key("u1");
    let hook = Arc::new(RecordingHook::default());
    let mut registry = HookRegistry::default();
    registry.add(hook.clone());

    let _ = evaluate(
        Some(&snapshot),
        "bool-flag",
        RequestedType::String,
        &ctx,
        &registry,
    );

    let calls = hook.calls.lock().unwrap().clone();
    assert_eq!(calls.len(), 3);
    assert_eq!(calls[0], "before:bool-flag");
    assert!(calls[1].starts_with("error:bool-flag:TypeMismatch"));
    assert_eq!(calls[2], "finally:bool-flag");
}
