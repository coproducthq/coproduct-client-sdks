use crate::snapshot::Flag;

/// Why a flag serves its off variation before the rule walker runs. These are the
/// only two pre-walk off-gate reasons: the later prerequisite-failed and
/// circuit-break paths are modeled with `EvaluationReason`, not this enum
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OffReason {
    /// isPaused is true, the global kill switch
    Paused,
    /// enabled is false in this environment
    Disabled,
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
