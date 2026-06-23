//! Segment + top-level Snapshot envelope

use serde::{Deserialize, Serialize};

use super::flag::Flag;
use super::rule::Operator;

/// A reusable group of users targetable by name from any flag's
/// `Condition::Segment { segment_key }`. `name` is carried in the SDK-facing
/// snapshot because tooling can surface the human-readable label on matches
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Segment {
    pub key: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub rules: Vec<SegmentRule>,
}

/// One rule inside a `Segment`. A flat attribute-operator-values triple
/// matching the platform's segment-rule wire schema, NOT a wrapper around the
/// recursive `Condition` tree. Segments resolve with OR semantics across their
/// rules. Coverage and rollout do not apply at the segment level (membership
/// is binary)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SegmentRule {
    pub attribute: String,
    pub operator: Operator,
    #[serde(default)]
    pub values: Vec<String>,
}

/// Snapshot body. The server wraps this in an outer
/// `{ snapshot, sdkContext }` envelope. The version fence reads the inner
/// `schemaVersion` before paying the full deserialization cost (see
/// `check_envelope_schema_version`)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Snapshot {
    /// Wire field `schemaVersion`, read by the fence before full parse
    #[serde(rename = "schemaVersion")]
    pub schema_version: u32,
    #[serde(rename = "generatedAt", default)]
    pub generated_at: String,
    pub version: u64,
    /// Identifies the environment this snapshot was generated for
    #[serde(default)]
    pub environment: EnvironmentMetadata,
    #[serde(default)]
    pub flags: Vec<Flag>,
    #[serde(default)]
    pub segments: Vec<Segment>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnvironmentMetadata {
    #[serde(default)]
    pub slug: String,
    #[serde(rename = "projectKey", default)]
    pub project_key: String,
}

/// In-memory snapshot used by the evaluation pipeline. Wraps the wire-format
/// `Snapshot` and re-keys flags and segments as hash maps for O(1) lookup
#[derive(Debug, Clone, PartialEq)]
pub struct IndexedSnapshot {
    pub schema_version: u32,
    pub generated_at: String,
    pub version: u64,
    pub environment: EnvironmentMetadata,
    pub flags: std::collections::HashMap<String, Flag>,
    pub segments: std::collections::HashMap<String, Segment>,
}

impl IndexedSnapshot {
    /// Project the in-memory indexed snapshot back into the wire-format
    /// `Snapshot`, collecting the re-keyed flag and segment maps into the vecs
    /// the wire shape uses. The inverse of `From<Snapshot>` for persistence
    pub fn to_wire(&self) -> Snapshot {
        Snapshot {
            schema_version: self.schema_version,
            generated_at: self.generated_at.clone(),
            version: self.version,
            environment: self.environment.clone(),
            flags: self.flags.values().cloned().collect(),
            segments: self.segments.values().cloned().collect(),
        }
    }
}

impl From<Snapshot> for IndexedSnapshot {
    fn from(wire: Snapshot) -> Self {
        let flags = wire.flags.into_iter().map(|f| (f.key.clone(), f)).collect();
        let segments = wire
            .segments
            .into_iter()
            .map(|s| (s.key.clone(), s))
            .collect();
        Self {
            schema_version: wire.schema_version,
            generated_at: wire.generated_at,
            version: wire.version,
            environment: wire.environment,
            flags,
            segments,
        }
    }
}

/// Server-derived geo attributes, merged at the LOWEST
/// evaluation-context precedence
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SdkContext {
    #[serde(default)]
    pub country: Option<String>,
    #[serde(default)]
    pub continent: Option<String>,
    /// ISO 3166-2 region code (e.g. `"US-CA"`), camelCase on the wire
    #[serde(default, rename = "regionCode")]
    pub region_code: Option<String>,
    #[serde(default)]
    pub city: Option<String>,
    /// IANA timezone name. Always populated by the server, defaults to
    /// `"UTC"` when the server returns no timezone
    pub timezone: String,
}
