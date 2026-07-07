use crate::error::EvaluationErrorCode;
use crate::pipeline::{EvaluationOutcome, EvaluationReason};
use crate::snapshot::VariationValue;

/// Details payload shaped to match the OpenFeature `FlagEvaluationDetails<T>`.
/// The layout is OpenFeature-shaped, but the values are not a drop-in for an
/// OpenFeature provider: this SDK serves the off value on a circuit break where
/// OpenFeature would serve the caller default, so a provider layered on this
/// surface maps that one served-with-error case back to the default itself
/// (see `build_details`)
#[derive(Debug, Clone, PartialEq)]
pub struct FlagEvaluationDetails<T> {
    pub value: T,
    pub variant: Option<String>,
    pub reason: Reason,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

/// OpenFeature reason vocabulary for the host-facing surface. `Static` and
/// `Unknown` are reserved for OpenFeature completeness and are not produced by
/// `map_reason`, which covers every pipeline reason with the other four
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
/// and a projection that yields Ok(T) on a type match or Err on a type mismatch.
///
/// A resolved variation that projects is served even when the outcome carries an
/// error code: a RULE_CIRCUIT_BREAK resolves to the off variation, and the plain
/// getters and observers serve that off value, so the detail getters return the
/// same value rather than the caller default. The error reason and code are still
/// reported, so a circuit break shows the off value with reason ERROR and code
/// RULE_CIRCUIT_BREAK. This deliberately diverges from OpenFeature's
/// error-serves-default convention; an OpenFeature provider layered on this
/// surface maps a served-with-error result back to the default itself. The caller
/// default is served only when no variation projects: provider-not-ready,
/// flag-not-found, or a stored value whose type does not match the getter
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
    // Serve a resolved variation whenever it projects, keying on projection
    // success rather than the error code so a circuit-break-to-off serves the off
    // value while carrying the error reason and code intact
    if let Some(value) = value {
        if let Ok(projected) = project(value) {
            let (reason, error_code, error_message) = match outcome.error_code {
                Some(code) => (
                    Reason::Error,
                    Some(code.as_wire().to_string()),
                    outcome.error_message,
                ),
                None => (map_reason(outcome.reason), None, None),
            };
            return FlagEvaluationDetails {
                value: projected,
                variant: outcome.variation_key,
                reason,
                error_code,
                error_message,
                flag_key,
            };
        }
        // The resolved variation's stored value does not match the getter type
        return FlagEvaluationDetails {
            value: default,
            variant: None,
            reason: Reason::Error,
            error_code: Some(EvaluationErrorCode::TypeMismatch.as_wire().to_string()),
            error_message: Some("flag type does not match getter".to_string()),
            flag_key,
        };
    }

    // No variation resolved. Report the outcome's own error, or flag-not-found when
    // it carried none
    let (code, message) = match outcome.error_code {
        Some(code) => (code.as_wire().to_string(), outcome.error_message),
        None => (
            EvaluationErrorCode::FlagNotFound.as_wire().to_string(),
            Some("flag or variation not found".to_string()),
        ),
    };
    FlagEvaluationDetails {
        value: default,
        variant: None,
        reason: Reason::Error,
        error_code: Some(code),
        error_message: message,
        flag_key,
    }
}
