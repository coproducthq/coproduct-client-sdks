//! Tolerant `Coverage` coalesce.
//!
//! Three branches:
//! - Absent (`{}`) coalesces to `10000`. A legacy rule with no coverage field
//!   was serving everyone, so this preserves intent.
//! - Present finite number truncates toward zero and clamps to `[0, 10000]`.
//! - Present non-finite (`null`, string, bool, object, array, NaN, +/-Inf)
//!   coalesces to `0`. Corruption fails closed: the rule then includes no one
//!   and the walker falls through to the next.
//!
//! A plain `Option<u32>` with `#[serde(default)]` would collapse absent and
//! present-null into the same `None`, silently turning a `null` into full
//! inclusion (fail open). The implementation therefore inspects a captured
//! `serde_json::Value` and branches explicitly

use serde::{Deserialize, Deserializer, Serialize};

/// Normalized coverage value in basis points, always `0..=10000`
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(transparent)]
pub struct Coverage(pub u32);

impl Default for Coverage {
    /// Absent `coverage` field defaults to 10000 (everyone in). Present-null
    /// goes through the custom deserializer below and maps to `Coverage(0)`
    fn default() -> Self {
        Coverage(10000)
    }
}

/// A bare `Coverage` coalesces the same way the `deserialize_coverage` field
/// helper does. Kept because round-trip deserialization of a `Coverage` value not
/// behind the field `deserialize_with` needs the trait impl
impl<'de> Deserialize<'de> for Coverage {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let v = serde_json::Value::deserialize(deserializer)?;
        Ok(coalesce_coverage_value(v))
    }
}

/// Deserializer for the `coverage` field. Serde calls this only when the field
/// is present, so `Value::Null` here means the wire had an explicit `null`,
/// distinct from absence (which `#[serde(default)]` on the field handles by
/// calling `Coverage::default()`). Taking `Value` (not `Option<Value>`) keeps
/// the absent-vs-null distinction alive
pub fn deserialize_coverage<'de, D>(deserializer: D) -> Result<Coverage, D::Error>
where
    D: Deserializer<'de>,
{
    let v = serde_json::Value::deserialize(deserializer)?;
    Ok(coalesce_coverage_value(v))
}

/// The pure coalesce. Mirrors the platform's coverage coalescing: a finite
/// number in `[0, 10000]` is clamped and truncated toward zero, anything
/// non-finite or non-number fails closed to `Coverage(0)`. Absence is handled
/// by the field's `#[serde(default)]` at the struct boundary, not here
pub fn coalesce_coverage_value(v: serde_json::Value) -> Coverage {
    match v {
        serde_json::Value::Null => Coverage(0),
        serde_json::Value::Number(n) => match n.as_f64() {
            Some(f) if f.is_finite() => {
                let truncated = f.trunc();
                if truncated <= 0.0 {
                    Coverage(0)
                } else if truncated >= 10000.0 {
                    Coverage(10000)
                } else {
                    Coverage(truncated as u32)
                }
            }
            _ => Coverage(0),
        },
        _ => Coverage(0),
    }
}
