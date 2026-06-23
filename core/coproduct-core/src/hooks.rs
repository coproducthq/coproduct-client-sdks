use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::Mutex;

use crate::error::EvaluationErrorCode;
use crate::observer::FlagValue;

/// The four stages of a single typed-getter evaluation. A getter fires `Before`,
/// then exactly one of `After` (success) or `Error` (failure), then `Finally`
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EvaluationStage {
    Before,
    After,
    Error,
    Finally,
}

/// The requested-getter type that triggered an evaluation. This is the type the
/// caller asked for at the getter surface and is distinct from the wire flag
/// type in `crate::snapshot::FlagType`: the getter type carries `Int`, which the
/// wire type folds into `Number`
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlagType {
    Bool,
    String,
    Int,
    Number,
    Json,
}

/// Snapshot of one getter evaluation handed to every hook stage. The context is
/// built at `Before` with the flag key, requested type, and default value, then
/// enriched with the resolved value and any error code before the terminal
/// stages fire
#[derive(Debug, Clone)]
pub struct HookContext {
    flag_key: String,
    r#type: FlagType,
    default_value: FlagValue,
    value: Option<FlagValue>,
    error_code: Option<EvaluationErrorCode>,
}

impl HookContext {
    pub fn new(flag_key: String, flag_type: FlagType, default_value: FlagValue) -> Self {
        Self {
            flag_key,
            r#type: flag_type,
            default_value,
            value: None,
            error_code: None,
        }
    }

    pub fn flag_key(&self) -> &str {
        &self.flag_key
    }

    pub fn flag_type(&self) -> FlagType {
        self.r#type
    }

    pub fn default_value(&self) -> &FlagValue {
        &self.default_value
    }

    pub fn value(&self) -> Option<&FlagValue> {
        self.value.as_ref()
    }

    pub fn error_code(&self) -> Option<EvaluationErrorCode> {
        self.error_code
    }

    pub fn with_value(mut self, value: FlagValue) -> Self {
        self.value = Some(value);
        self
    }

    pub fn with_error(mut self, code: EvaluationErrorCode) -> Self {
        self.error_code = Some(code);
        self
    }
}

/// Customer-facing evaluation hook. Fired synchronously around each typed-getter
/// call so a hook observes a single bracketed evaluation. The callback is sync
/// because the getters are sync: an async hook fired from a sync path could not
/// be awaited and would be dropped without running
pub trait EvaluationHook: Send + Sync + std::fmt::Debug {
    fn on_stage(&self, stage: EvaluationStage, ctx: &HookContext);
}

/// Opaque handle returned from registering a hook. Cancellation is idempotent: a
/// second cancel is a no-op, and dropping the handle cancels the registration
#[derive(Debug)]
pub struct HookHandle {
    id: u64,
    cancelled: AtomicBool,
    registry: Arc<HookRegistry>,
}

impl HookHandle {
    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    pub fn cancel(&self) {
        if self.cancelled.swap(true, Ordering::AcqRel) {
            return;
        }
        self.registry.remove(self.id);
    }

    /// A pre-cancelled hook handle handed back when `add_evaluation_hook` is
    /// called after shutdown. It references a throwaway registry and starts
    /// cancelled, so its `cancel` and `Drop` are no-ops and it never registers
    /// anything
    pub(crate) fn cancelled_stub() -> Self {
        Self {
            id: u64::MAX,
            cancelled: AtomicBool::new(true),
            registry: HookRegistry::new(),
        }
    }
}

impl Drop for HookHandle {
    fn drop(&mut self) {
        self.cancel();
    }
}

/// Registry of evaluation hooks owned by the client. Hooks are fired in
/// registration order: each getter takes a value snapshot of the registered
/// hooks and calls every one for the stage
#[derive(Debug, Default)]
pub struct HookRegistry {
    next_id: AtomicU64,
    entries: Mutex<BTreeMap<u64, Arc<dyn EvaluationHook>>>,
}

impl HookRegistry {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn register(self: &Arc<Self>, hook: Arc<dyn EvaluationHook>) -> Arc<HookHandle> {
        let id = self.next_id.fetch_add(1, Ordering::AcqRel);
        self.entries.lock().insert(id, hook);
        Arc::new(HookHandle {
            id,
            cancelled: AtomicBool::new(false),
            registry: self.clone(),
        })
    }

    pub fn remove(&self, id: u64) {
        self.entries.lock().remove(&id);
    }

    pub fn snapshot(&self) -> Vec<Arc<dyn EvaluationHook>> {
        self.entries.lock().values().cloned().collect()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.lock().is_empty()
    }

    /// Fire one stage at every registered hook. The hook list is snapshotted out
    /// of the lock first so a hook callback can register or cancel without
    /// deadlocking on the registry mutex
    pub fn fire(&self, stage: EvaluationStage, ctx: &HookContext) {
        for hook in self.snapshot() {
            hook.on_stage(stage, ctx);
        }
    }

    pub fn drain(&self) {
        self.entries.lock().clear();
    }
}
