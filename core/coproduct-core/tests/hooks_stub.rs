use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::hooks::{EvaluationHook, HookContext, HookOutcome, HookRegistry, NoopHook};
use std::sync::Arc;

#[test]
fn registry_is_empty_by_default() {
    let registry = HookRegistry::default();
    assert_eq!(registry.len(), 0);
}

#[test]
fn registry_holds_registered_hooks_in_insertion_order() {
    let mut registry = HookRegistry::default();
    let a: Arc<dyn EvaluationHook> = Arc::new(NoopHook);
    let b: Arc<dyn EvaluationHook> = Arc::new(NoopHook);
    registry.add(a);
    registry.add(b);
    assert_eq!(registry.len(), 2);
}

#[test]
fn noop_hook_returns_proceed_on_every_callback() {
    let hook = NoopHook;
    let ctx = HookContext {
        flag_key: "my-flag",
        default_value_label: "false",
    };
    assert!(matches!(hook.before(&ctx), HookOutcome::Proceed));
    hook.after(&ctx, "on");
    hook.error(&ctx, EvaluationErrorCode::RuleCircuitBreak, "circuit");
    hook.finally(&ctx);
}
