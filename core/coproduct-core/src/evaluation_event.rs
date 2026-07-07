use std::sync::Arc;

use parking_lot::RwLock;
use time::OffsetDateTime;

use crate::error::EvaluationErrorCode;
use crate::hooks::FlagType;
use crate::observer::FlagValue;

/// Why an evaluation resolved the way it did, mirrored onto the analytics event
/// surface. Distinct from the internal pipeline reason so the event type stays
/// stable even if the pipeline grows new internal states
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvaluationReason {
    TargetingMatch,
    Fallthrough,
    Off,
    PrerequisiteFailed,
    Error,
}

/// One flag evaluation rendered as an analytics record. Emitted after every
/// typed-getter call so a host listener can forward it to an analytics sink. The
/// resolved value, the caller default, the served variant, the reason, and any
/// error code are captured together with the wall-clock evaluation time
#[derive(Debug, Clone, PartialEq)]
pub struct EvaluationEvent {
    pub flag_key: String,
    pub flag_type: FlagType,
    pub value: FlagValue,
    pub default_value: FlagValue,
    pub variant: Option<String>,
    pub reason: EvaluationReason,
    /// Identifier of the targeting rule that matched, when one did. The pipeline
    /// outcome does not carry the matched rule id, so this stays `None` unless that
    /// plumbing is added. Typed as a string to match the rule identifier shape
    pub rule_id: Option<String>,
    pub error_code: Option<EvaluationErrorCode>,
    pub evaluated_at: OffsetDateTime,
}

/// Host-supplied sink for evaluation events. Called synchronously from the typed
/// getter that produced the event, so implementations must not block
pub trait EvaluationListener: Send + Sync + std::fmt::Debug {
    fn on_evaluation(&self, event: &EvaluationEvent);
}

/// Holds the single registered evaluation listener and forwards events to it.
/// A getter always builds and emits its event; with no listener set, `emit` is a
/// cheap read-and-return
#[derive(Debug, Default)]
pub struct EvaluationEventDispatcher {
    listener: RwLock<Option<Arc<dyn EvaluationListener>>>,
}

impl EvaluationEventDispatcher {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn set(&self, listener: Arc<dyn EvaluationListener>) {
        *self.listener.write() = Some(listener);
    }

    pub fn clear(&self) {
        *self.listener.write() = None;
    }

    pub fn emit(&self, event: &EvaluationEvent) {
        let listener = self.listener.read().clone();
        if let Some(listener) = listener {
            listener.on_evaluation(event);
        }
    }
}
