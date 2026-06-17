use serde::{Deserialize, Serialize};

use super::rule::TargetingRule;
use super::variation::Variation;

/// One feature flag inside the snapshot. Outer fields use camelCase
/// (`isPaused`, `offVariation`) to match the server's snapshot format
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Flag {
    pub key: String,
    #[serde(rename = "type")]
    pub r#type: FlagType,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(rename = "isPaused", default)]
    pub is_paused: bool,
    #[serde(default)]
    pub variations: Vec<Variation>,
    #[serde(rename = "offVariation", default)]
    pub off_variation: Option<String>,
    #[serde(rename = "fallthroughVariation", default)]
    pub fallthrough_variation: Option<String>,
    #[serde(rename = "targetingRules", default)]
    pub targeting_rules: Vec<TargetingRule>,
    #[serde(default)]
    pub prerequisites: Vec<Prerequisite>,
    #[serde(default)]
    pub experiment: Option<serde_json::Value>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FlagType {
    #[serde(rename = "BOOL")]
    Bool,
    #[serde(rename = "STRING")]
    String,
    #[serde(rename = "NUMBER")]
    Number,
    #[serde(rename = "JSON")]
    Json,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Prerequisite {
    #[serde(rename = "flagKey")]
    pub flag_key: String,
    pub variation: String,
}
