//! Snapshot wire format.
//!
//! All public types in this module are pure data with `Serialize`/`Deserialize`
//! impls. Evaluation logic lives in `eval.rs` and walks these types read-only

mod coverage;
mod flag;
mod rule;
mod segment;
mod variation;

pub use coverage::{Coverage, coalesce_coverage_value, deserialize_coverage};
pub use flag::{Flag, FlagType, Prerequisite};
pub use rule::{Condition, Operator, Rollout, TargetingRule, WeightedVariation};
pub use segment::{
    EnvironmentMetadata, IndexedSnapshot, SdkContext, Segment, SegmentRule, Snapshot,
};
pub use variation::{Variation, VariationValue};

// Schema-version fence over the snapshot envelope

use serde::Deserialize;
use serde_json::value::RawValue;

use crate::error::InitError;

/// The single schemaVersion the SDK supports. Moves only with a coordinated
/// four-platform release
pub const SUPPORTED_SCHEMA_VERSION: u32 = 1;

/// Top-level envelope of the GET /v1/snapshot response. The server response
/// body is exactly `{ snapshot, sdkContext }`. The `schemaVersion` lives inside
/// the `snapshot` body and is NOT a top-level envelope field. Both `snapshot`
/// and `sdkContext` are held as `RawValue` so neither is fully parsed until the
/// schemaVersion fence has cleared on the snapshot body
#[derive(Debug, Deserialize)]
pub struct SnapshotEnvelope<'a> {
    #[serde(borrow)]
    pub snapshot: &'a RawValue,
    /// Server-derived geo attributes (country, continent, regionCode, city, timezone)
    /// that sit alongside `snapshot` in the response, NOT inside the snapshot
    /// body. The SDK merges them at the lowest precedence in the evaluation
    /// context
    #[serde(rename = "sdkContext", default, borrow)]
    pub sdk_context: Option<&'a RawValue>,
}

/// Cheap pre-parse helper: extract just the `schemaVersion` from inside the
/// snapshot body without deserializing the full structure. Used by the fence
/// so an unsupported snapshot does not pay the full deserialization cost
#[derive(Deserialize)]
struct SnapshotVersionOnly {
    #[serde(rename = "schemaVersion")]
    schema_version: u32,
}

/// Parse the envelope, then extract the snapshot body's `schemaVersion` and
/// verify it matches `SUPPORTED_SCHEMA_VERSION`. Returns the inner snapshot
/// body as a `RawValue` for the caller to deserialize against the wire-format
/// types.
///
/// Returns `InitError::UnsupportedSchemaVersion` when the version differs.
/// Returns a generic InitError-mapped parse error when the envelope or the
/// snapshot's version field is malformed
pub fn check_envelope_schema_version(raw: &str) -> Result<&RawValue, InitError> {
    let envelope: SnapshotEnvelope =
        serde_json::from_str(raw).map_err(|e| InitError::InvalidConfig {
            field: "snapshotEnvelope".to_string(),
            reason: format!("envelope parse failed: {e}"),
        })?;

    let version: SnapshotVersionOnly =
        serde_json::from_str(envelope.snapshot.get()).map_err(|e| InitError::InvalidConfig {
            field: "snapshot.schemaVersion".to_string(),
            reason: format!("snapshot body missing or malformed schemaVersion: {e}"),
        })?;

    if version.schema_version != SUPPORTED_SCHEMA_VERSION {
        return Err(InitError::UnsupportedSchemaVersion {
            actual: version.schema_version,
            supported: SUPPORTED_SCHEMA_VERSION,
        });
    }

    Ok(envelope.snapshot)
}
