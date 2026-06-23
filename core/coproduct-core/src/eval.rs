//! Evaluation entry points.
//!
//! The eight-step evaluation pipeline lives in `crate::pipeline`, the condition
//! tree in `crate::condition`, and the rule walker in `crate::rule_walker`. This
//! module is reserved for higher-level evaluation glue

use crate::context::EvaluationContext;
use crate::observer::FlagValue;
use crate::pipeline::{RequestedType, evaluate};
use crate::snapshot::{FlagType, IndexedSnapshot, VariationValue};

/// Resolve a flag for the observer fanout path.
///
/// Returns `None` when `key` is absent from the snapshot so callers can treat a
/// missing flag distinctly from a flag that resolved to a value. When the flag
/// is present the result is `Some(FlagValue)` whose variant matches the flag's
/// declared `FlagType`, carrying the value the matching typed getter would
/// return for the same context.
///
/// The evaluation runs through the same `crate::pipeline::evaluate` path the
/// typed getters use, with no evaluation hooks. A present flag always yields a
/// concrete value: if the pipeline does not resolve a usable variation the
/// type-appropriate fallback is used (false, empty string, 0, 0.0, or JSON
/// null) so a found flag never collapses back to `None`.
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
        FlagType::Bool => FlagValue::Bool(match resolved {
            Some(VariationValue::Bool(b)) => b,
            _ => false,
        }),
        FlagType::String => FlagValue::String(match resolved {
            Some(VariationValue::String(s)) => s,
            _ => String::new(),
        }),
        FlagType::Number => match resolved {
            Some(VariationValue::Number(n)) => FlagValue::Number(n),
            _ => FlagValue::Number(0.0),
        },
        FlagType::Json => FlagValue::Json(match resolved {
            Some(VariationValue::Json(j)) => j,
            _ => serde_json::Value::Null,
        }),
    };

    Some(value)
}
