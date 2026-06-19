use std::sync::Arc;

use crate::error::EvaluationErrorCode;

/// Snapshot of pipeline state passed to every hook callback. The fields here
/// are intentionally minimal so the pipeline can call hook entry points without
/// forward references to the richer evaluation-event shape
pub struct HookContext<'a> {
    pub flag_key: &'a str,
    pub default_value_label: &'a str,
}

/// Result of a `before` hook. Only `Proceed` exists today. The enum is reserved
/// so a future revision can add a short-circuit arm without changing callers
pub enum HookOutcome {
    Proceed,
}

/// Per-evaluation interception surface backing the public hook API. The trait
/// shape exists so the pipeline can call every hook entry point uniformly
pub trait EvaluationHook: Send + Sync {
    fn before(&self, _ctx: &HookContext<'_>) -> HookOutcome {
        HookOutcome::Proceed
    }
    fn after(&self, _ctx: &HookContext<'_>, _variant: &str) {}
    fn error(&self, _ctx: &HookContext<'_>, _code: EvaluationErrorCode, _message: &str) {}
    fn finally(&self, _ctx: &HookContext<'_>) {}
}

/// A hook that does nothing. The default registry is empty. This type exists for
/// tests and for hosts that want to register a passthrough
pub struct NoopHook;
impl EvaluationHook for NoopHook {}

/// Insertion-ordered registry of evaluation hooks owned by the client
#[derive(Default)]
pub struct HookRegistry {
    hooks: Vec<Arc<dyn EvaluationHook>>,
}

impl HookRegistry {
    pub fn add(&mut self, hook: Arc<dyn EvaluationHook>) {
        self.hooks.push(hook);
    }

    pub fn len(&self) -> usize {
        self.hooks.len()
    }

    pub fn is_empty(&self) -> bool {
        self.hooks.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = &Arc<dyn EvaluationHook>> {
        self.hooks.iter()
    }
}
