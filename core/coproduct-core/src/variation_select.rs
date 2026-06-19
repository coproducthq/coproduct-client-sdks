use crate::snapshot::Flag;
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OffReason {
    /// isPaused is true, the global kill switch
    Paused,
    /// enabled is false in this environment
    Disabled,
    /// A prerequisite flag did not resolve to its required variation
    PrerequisiteFailed,
    /// A condition tripped RULE_CIRCUIT_BREAK during the rule walk
    CircuitBreak,
}

#[derive(Debug, Clone, PartialEq)]
pub struct OffSelection {
    pub reason: OffReason,
    pub variation_key: Option<String>,
    pub value: Option<Value>,
}

/// Returns `Some(reason)` when the flag should serve its off variation before
/// the rule walker even runs. Paused beats disabled in the reported reason
/// because the kill switch is the user-visible state. The two wire fields are
/// independent and may both be true.
///
/// This helper is the single source of truth for the off-gate. The evaluation
/// pipeline and the conformance harness both call it instead of inlining the
/// is_paused and enabled checks, so the conformance corpus validates the same
/// code path production uses
pub fn should_serve_off(flag: &Flag) -> Option<OffReason> {
    if flag.is_paused {
        return Some(OffReason::Paused);
    }
    if !flag.enabled {
        return Some(OffReason::Disabled);
    }
    None
}

/// Resolve the off-variation value for a given reason. The reason is carried
/// through so the caller can populate the evaluation details. The caller falls
/// back to the developer-supplied default when the value is `None`
pub fn select_off(flag: &Flag, reason: OffReason) -> OffSelection {
    let variation_key = flag.off_variation.clone();
    let value = variation_key.as_ref().and_then(|k| resolve(flag, k));
    OffSelection {
        reason,
        variation_key,
        value,
    }
}

/// Look up a variation by key and project its typed value to JSON. Returns
/// `None` when the key is absent or the value cannot be represented
fn resolve(flag: &Flag, variation_key: &str) -> Option<Value> {
    flag.variations
        .iter()
        .find(|v| v.key == variation_key)
        .and_then(|v| serde_json::to_value(&v.value).ok())
}
