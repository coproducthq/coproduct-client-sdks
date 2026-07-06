use crate::error::EvaluationErrorCode;
use crate::pipeline::{EvaluationOutcome, EvaluationReason};
use crate::snapshot::VariationValue;

/// Details payload shaped to match the OpenFeature `FlagEvaluationDetails<T>`
/// so a future OpenFeature provider can pass it through without translation
#[derive(Debug, Clone, PartialEq)]
pub struct FlagEvaluationDetails<T> {
    pub value: T,
    pub variant: Option<String>,
    pub reason: Reason,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

/// OpenFeature reason vocabulary for the host-facing surface
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reason {
    Static,
    Default,
    TargetingMatch,
    Disabled,
    Error,
    Unknown,
}

impl Reason {
    pub fn wire(self) -> &'static str {
        match self {
            Reason::Static => "STATIC",
            Reason::Default => "DEFAULT",
            Reason::TargetingMatch => "TARGETING_MATCH",
            Reason::Disabled => "DISABLED",
            Reason::Error => "ERROR",
            Reason::Unknown => "UNKNOWN",
        }
    }
}

/// Map the internal pipeline reason to the OpenFeature vocabulary. A fallthrough
/// resolution maps to `Default` because OpenFeature uses DEFAULT for a flag that
/// served its default rollout
fn map_reason(reason: EvaluationReason) -> Reason {
    match reason {
        EvaluationReason::TargetingMatch => Reason::TargetingMatch,
        EvaluationReason::Fallthrough => Reason::Default,
        EvaluationReason::Off => Reason::Disabled,
        EvaluationReason::PrerequisiteFailed => Reason::Disabled,
        EvaluationReason::Error => Reason::Error,
    }
}

/// Build a typed details payload from the untyped outcome, the caller-resolved
/// variation value (None when the snapshot, flag, or variation lookup failed),
/// and a projection that yields Ok(T) on a type match or Err on a type mismatch
pub(crate) fn build_details<T, F>(
    flag_key: String,
    outcome: EvaluationOutcome,
    value: Option<VariationValue>,
    default: T,
    project: F,
) -> FlagEvaluationDetails<T>
where
    F: FnOnce(VariationValue) -> Result<T, ()>,
{
    if let Some(code) = outcome.error_code {
        return FlagEvaluationDetails {
            value: default,
            variant: None,
            reason: Reason::Error,
            error_code: Some(code.as_wire().to_string()),
            error_message: outcome.error_message,
            flag_key,
        };
    }

    let Some(value) = value else {
        return FlagEvaluationDetails {
            value: default,
            variant: None,
            reason: Reason::Error,
            error_code: Some(EvaluationErrorCode::FlagNotFound.as_wire().to_string()),
            error_message: Some("flag or variation not found".to_string()),
            flag_key,
        };
    };

    let reason = map_reason(outcome.reason);
    match project(value) {
        Ok(v) => FlagEvaluationDetails {
            value: v,
            variant: outcome.variation_key,
            reason,
            error_code: None,
            error_message: None,
            flag_key,
        },
        Err(()) => FlagEvaluationDetails {
            value: default,
            variant: None,
            reason: Reason::Error,
            error_code: Some(EvaluationErrorCode::TypeMismatch.as_wire().to_string()),
            error_message: Some("flag type does not match getter".to_string()),
            flag_key,
        },
    }
}
