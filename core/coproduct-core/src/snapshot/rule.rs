//! Targeting rule, condition tree, rollout, and the attribute operator set

use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::coverage::{Coverage, deserialize_coverage};

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
        use serde::de::Error;

        // Private helper that derive-deserializes the known node types. The
        // outer impl dispatches on `type` so an unrecognized node becomes
        // `Unknown { tag }` instead of a hard parse error
        #[derive(Deserialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        enum Known {
            Attribute {
                attribute: String,
                operator: Operator,
                #[serde(default)]
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
        }

        let value = serde_json::Value::deserialize(deserializer)?;
        let tag = value
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();

        match tag.as_str() {
            "attribute" | "segment" | "always" | "and" | "or" | "not" => {
                let known: Known = serde_json::from_value(value).map_err(Error::custom)?;
                Ok(match known {
                    Known::Attribute {
                        attribute,
                        operator,
                        values,
                    } => Condition::Attribute {
                        attribute,
                        operator,
                        values,
                    },
                    Known::Segment { segment_key } => Condition::Segment { segment_key },
                    Known::Always => Condition::Always,
                    Known::And { rules } => Condition::And { rules },
                    Known::Or { rules } => Condition::Or { rules },
                    Known::Not { rule } => Condition::Not { rule },
                })
            }
            _ => Ok(Condition::Unknown { tag }),
        }
    }
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
    pub percentage: u32,
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
