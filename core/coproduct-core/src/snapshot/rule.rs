//! Targeting rule, condition tree, rollout, and the attribute operator set

use std::collections::HashMap;

use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

use super::coverage::{Coverage, deserialize_coverage};
use super::segment::Segment;

/// One targeting rule.
///
/// Wire-format casing: snake_case field names inside the rule tree (this
/// struct, the condition tree, the rollout enum), camelCase at the
/// snapshot/flag envelope level (the `Flag` struct)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TargetingRule {
    pub rule_id: String,
    pub condition: Condition,
    #[serde(default, deserialize_with = "deserialize_coverage")]
    pub coverage: Coverage,
    pub rollout: Rollout,
    #[serde(default)]
    pub description: Option<String>,
}

/// Whether a condition tree contains anything this SDK build cannot evaluate:
/// an unknown node type, or an attribute condition whose operator is unknown.
/// Referenced segments are resolved and their rules scanned the same way, so an
/// unknown operator inside a segment fails the flag closed up front just as an
/// inline one does. The rule walker calls this up front for each rule so a flag
/// carrying anything unknown fails closed before any rule is evaluated,
/// independent of how the flag was constructed and of short-circuit order. A
/// missing segment is not unknown: a reference to a segment that is not in the
/// snapshot resolves to no-match during evaluation, not a circuit break, so the
/// scan leaves it to the walk
pub(crate) fn condition_contains_unknown(
    condition: &Condition,
    segments: &HashMap<String, Segment>,
) -> bool {
    match condition {
        Condition::Unknown { .. } => true,
        Condition::Attribute { operator, .. } => *operator == Operator::Unknown,
        Condition::Segment { segment_key } => segments.get(segment_key).is_some_and(|segment| {
            segment
                .rules
                .iter()
                .any(|rule| rule.operator == Operator::Unknown)
        }),
        Condition::And { rules } | Condition::Or { rules } => rules
            .iter()
            .any(|child| condition_contains_unknown(child, segments)),
        Condition::Not { rule } => condition_contains_unknown(rule, segments),
        Condition::Always => false,
    }
}

/// Condition tree. Variants match the platform schema's condition tree.
///
/// The `Unknown` arm catches forward-incompatible node types: the evaluator
/// trips RULE_CIRCUIT_BREAK on `Condition::Unknown` rather than panicking, and
/// `tag` carries the unrecognized node-type string so telemetry can attribute
/// the break. The hand-written `Deserialize` routes an unrecognized `type` to
/// `Unknown { tag }` instead of failing the whole snapshot parse
#[derive(Debug, Clone, PartialEq)]
pub enum Condition {
    Attribute {
        attribute: String,
        operator: Operator,
        values: Vec<String>,
    },
    Segment {
        segment_key: String,
    },
    Always,
    And {
        rules: Vec<Condition>,
    },
    Or {
        rules: Vec<Condition>,
    },
    Not {
        rule: Box<Condition>,
    },
    Unknown {
        tag: String,
    },
}

impl Serialize for Condition {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match self {
            Condition::Attribute {
                attribute,
                operator,
                values,
            } => {
                let mut map = serializer.serialize_map(Some(4))?;
                map.serialize_entry("type", "attribute")?;
                map.serialize_entry("attribute", attribute)?;
                map.serialize_entry("operator", operator)?;
                map.serialize_entry("values", values)?;
                map.end()
            }
            Condition::Segment { segment_key } => {
                let mut map = serializer.serialize_map(Some(2))?;
                map.serialize_entry("type", "segment")?;
                map.serialize_entry("segment_key", segment_key)?;
                map.end()
            }
            Condition::Always => {
                let mut map = serializer.serialize_map(Some(1))?;
                map.serialize_entry("type", "always")?;
                map.end()
            }
            Condition::And { rules } => {
                let mut map = serializer.serialize_map(Some(2))?;
                map.serialize_entry("type", "and")?;
                map.serialize_entry("rules", rules)?;
                map.end()
            }
            Condition::Or { rules } => {
                let mut map = serializer.serialize_map(Some(2))?;
                map.serialize_entry("type", "or")?;
                map.serialize_entry("rules", rules)?;
                map.end()
            }
            Condition::Not { rule } => {
                let mut map = serializer.serialize_map(Some(2))?;
                map.serialize_entry("type", "not")?;
                map.serialize_entry("rule", rule)?;
                map.end()
            }
            Condition::Unknown { tag } => {
                let mut map = serializer.serialize_map(Some(1))?;
                map.serialize_entry("type", tag)?;
                map.end()
            }
        }
    }
}

impl<'de> Deserialize<'de> for Condition {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = Value::deserialize(deserializer)?;
        Ok(Self::from_value(raw))
    }
}

impl Condition {
    /// Tolerant decode. An unrecognized node type, or a known type with a
    /// structurally invalid body, becomes `Unknown { tag }` instead of failing
    /// the whole snapshot parse, so a single bad subtree from a newer server
    /// cannot wedge an otherwise-valid snapshot. The rule walker then trips
    /// RULE_CIRCUIT_BREAK on any rule that references an `Unknown` node
    fn from_value(raw: Value) -> Condition {
        let obj = match raw.as_object() {
            Some(o) => o,
            None => {
                return Condition::Unknown {
                    tag: "non_object".into(),
                };
            }
        };
        let tag = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");
        match tag {
            "always" => Condition::Always,
            "attribute" => {
                let attribute = obj.get("attribute").and_then(|v| v.as_str());
                let operator = obj
                    .get("operator")
                    .and_then(|v| serde_json::from_value::<Operator>(v.clone()).ok());
                // The wire `values` field must be present, be an array, and hold
                // only strings. A missing field, a non-array, or any non-string
                // entry makes the whole node decode to Unknown so a structurally
                // invalid RHS fails the rule closed rather than silently repairing
                // into a node that could still match
                let values = obj.get("values").and_then(values_as_string_vec);
                match (attribute, operator, values) {
                    (Some(attribute), Some(operator), Some(values)) => Condition::Attribute {
                        attribute: attribute.to_string(),
                        operator,
                        values,
                    },
                    _ => Condition::Unknown {
                        tag: "attribute".into(),
                    },
                }
            }
            "segment" => match obj.get("segment_key").and_then(|v| v.as_str()) {
                Some(s) => Condition::Segment {
                    segment_key: s.to_string(),
                },
                None => Condition::Unknown {
                    tag: "segment".into(),
                },
            },
            "and" => match obj.get("rules").and_then(|v| v.as_array()) {
                Some(arr) => Condition::And {
                    rules: arr.iter().cloned().map(Condition::from_value).collect(),
                },
                None => Condition::Unknown { tag: "and".into() },
            },
            "or" => match obj.get("rules").and_then(|v| v.as_array()) {
                Some(arr) => Condition::Or {
                    rules: arr.iter().cloned().map(Condition::from_value).collect(),
                },
                None => Condition::Unknown { tag: "or".into() },
            },
            "not" => match obj.get("rule") {
                Some(inner) => Condition::Not {
                    rule: Box::new(Condition::from_value(inner.clone())),
                },
                None => Condition::Unknown { tag: "not".into() },
            },
            other => Condition::Unknown {
                tag: other.to_string(),
            },
        }
    }
}

/// Parse the wire `values` field of an attribute condition. Returns `None` when
/// the value is not an array or contains any non-string entry, which routes the
/// surrounding node to `Unknown` so a malformed RHS fails closed
fn values_as_string_vec(v: &Value) -> Option<Vec<String>> {
    let arr = v.as_array()?;
    let mut out = Vec::with_capacity(arr.len());
    for item in arr {
        out.push(item.as_str()?.to_string());
    }
    Some(out)
}

/// How a matching rule picks a flag value: either a single fixed variation
/// or a weighted split among several. The `Unknown` arm catches future
/// rollout shapes the SDK does not understand, so the rule fails safely
/// instead of crashing
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Rollout {
    Variation {
        variation: String,
    },
    Weights {
        weights: Vec<WeightedVariation>,
    },
    #[serde(other)]
    Unknown,
}

/// One slice of a weighted-split rollout. `percentage` is an integer in
/// `0..=100`. The weights of a single rollout sum to 100. Rule coverage is
/// the separate basis-points gate in `TargetingRule.coverage`
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WeightedVariation {
    pub variation_key: String,
    #[serde(default, deserialize_with = "deserialize_percentage")]
    pub percentage: u32,
}

/// Coalesce a wire `percentage` the way `coverage` coalesces its basis points: a
/// finite number truncates toward zero and clamps to `0..=100`, and anything
/// non-finite or non-numeric fails closed to `0`. A malformed weight therefore
/// sanitizes to a safe value instead of failing the whole snapshot parse
fn deserialize_percentage<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    Ok(match value {
        Value::Number(n) => match n.as_f64() {
            Some(f) if f.is_finite() => f.trunc().clamp(0.0, 100.0) as u32,
            _ => 0,
        },
        _ => 0,
    })
}

/// The attribute operator set. `is_set` / `is_not_set` are zero-value
/// operators dispatched by the condition-tree evaluator (they must observe a
/// missing attribute), not by the value-comparison `evaluate`.
///
/// The `Unknown` arm lets a future server release ship a new operator without
/// aborting the snapshot parse on this SDK version. The evaluator treats
/// `Operator::Unknown` as RULE_CIRCUIT_BREAK
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Operator {
    Equals,
    NotEquals,
    Gt,
    Gte,
    Lt,
    Lte,
    In,
    NotIn,
    StartsWith,
    EndsWith,
    Contains,
    NotContains,
    SemVerEq,
    SemVerGt,
    SemVerGte,
    SemVerLt,
    SemVerLte,
    IsSet,
    IsNotSet,
    #[serde(other)]
    Unknown,
}
