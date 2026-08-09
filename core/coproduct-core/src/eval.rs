//! Evaluation entry points.
//!
//! The evaluation pipeline lives in `crate::pipeline`, the condition tree in
//! `crate::condition`, and the rule walker in `crate::rule_walker`. This module is
//! reserved for higher-level evaluation glue

use crate::context::EvaluationContext;
use crate::observer::FlagValue;
use crate::pipeline::{RequestedType, evaluate};
use crate::snapshot::{FlagType, IndexedSnapshot, VariationValue};

/// Smallest `f64` that is too large for an `i64`. `i64::MAX` is not exactly
/// representable as an `f64` and rounds up to 2^63, so an upper bound written as
/// `value > i64::MAX as f64` admits exactly 2^63, which the float-to-integer cast
/// then saturates to `i64::MAX`. Comparing against 2^63 exclusively keeps an
/// unrepresentable value unavailable instead of silently clamping it. `i64::MIN`
/// is exactly representable, so the lower bound stays inclusive
const INT_UPPER_EXCLUSIVE: f64 = 9_223_372_036_854_775_808.0;

/// Project a NUMBER flag value onto an integer by truncating toward zero.
/// Returns `None` when the truncated value is not finite or not representable as
/// an `i64`. The integer getters and the FFI integer observations share this so
/// an observation always equals `get_int` for the same value
pub fn number_to_int(value: f64) -> Option<i64> {
    let truncated = value.trunc();
    if !truncated.is_finite() || truncated < i64::MIN as f64 || truncated >= INT_UPPER_EXCLUSIVE {
        return None;
    }
    Some(truncated as i64)
}

/// Resolve a flag for the observer fanout path.
///
/// Returns `None` when `key` is absent from the snapshot so callers can treat a
/// missing flag distinctly from a flag that resolved to a value. When the flag
/// is present the result is `Some(FlagValue)` whose variant matches the flag's
/// declared `FlagType`, carrying the value the matching typed getter would
/// return for the same context.
///
/// The evaluation runs through the same `crate::pipeline::evaluate` path the
/// typed getters use, with no evaluation hooks. A present flag whose resolved
/// variation does not match its declared `FlagType` has no usable value, so
/// evaluation is unavailable (`None`) rather than a type zero value, and the
/// caller falls back to its own default. A usable resolution, including a
/// circuit-break off variation whose value matches the type, still yields
/// `Some(FlagValue)`.
pub fn evaluate_for_observer(
    snapshot: &IndexedSnapshot,
    key: &str,
    context: &EvaluationContext,
) -> Option<FlagValue> {
    let flag = snapshot.flags.get(key)?;
    let flag_type = flag.r#type;
    let requested_type = match flag_type {
        FlagType::Bool => RequestedType::Bool,
        FlagType::String => RequestedType::String,
        FlagType::Number => RequestedType::Number,
        FlagType::Json => RequestedType::Json,
        // An unknown flag type has no usable value, so it is omitted from
        // observation the same way its getters fail closed to the default
        FlagType::Unknown => return None,
    };

    let outcome = evaluate(Some(snapshot), key, requested_type, context);

    let resolved = outcome.variation_key.as_ref().and_then(|variation_key| {
        snapshot
            .flags
            .get(key)?
            .variations
            .iter()
            .find(|var| &var.key == variation_key)
            .map(|var| &var.value)
            .cloned()
    });

    let value = match flag_type {
        FlagType::Bool => match resolved {
            Some(VariationValue::Bool(b)) => FlagValue::Bool(b),
            _ => return None,
        },
        FlagType::String => match resolved {
            Some(VariationValue::String(s)) => FlagValue::String(s),
            _ => return None,
        },
        FlagType::Number => match resolved {
            Some(VariationValue::Number(n)) => FlagValue::Number(n),
            _ => return None,
        },
        FlagType::Json => match resolved {
            Some(VariationValue::Json(j)) => FlagValue::Json(j),
            _ => return None,
        },
        // Unreachable: an unknown type returned above. Kept for exhaustiveness
        FlagType::Unknown => return None,
    };

    Some(value)
}
