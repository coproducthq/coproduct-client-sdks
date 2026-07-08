//! Snapshot wire format.
//!
//! The wire-format types are pure data with `Serialize`/`Deserialize` impls. The
//! evaluation modules (`pipeline`, `condition`, `rule_walker`) walk them
//! read-only. The `ConditionOutcome` enum also lives here so the operator and
//! condition layers share one outcome vocabulary

mod coverage;
mod flag;
mod outcome;
mod rule;
mod segment;
mod variation;

pub use crate::condition::evaluate_condition;
pub use coverage::{Coverage, coalesce_coverage_value, deserialize_coverage};
pub use flag::{Flag, FlagType, Prerequisite};
pub use outcome::ConditionOutcome;
pub use rule::{Condition, Operator, Rollout, TargetingRule, WeightedVariation};
// Internal evaluation helper, not part of the public snapshot API
pub(crate) use rule::condition_contains_unknown;
pub use segment::{
    EnvironmentMetadata, IndexedSnapshot, SdkContext, Segment, SegmentRule, Snapshot, SnapshotView,
};
pub use variation::{Variation, VariationValue};

// Schema-version fence over the snapshot envelope

use serde::Deserialize;
use serde_json::value::RawValue;

/// The single schemaVersion the SDK supports. Moves only with a coordinated
/// four-platform release
pub const SUPPORTED_SCHEMA_VERSION: u32 = 1;

/// Failure from the pre-parse schema fence. A local error type, not an
/// `InitError`, because a malformed snapshot payload is a wire-data defect from
/// the server, not an init-time configuration problem. Mapping it onto
/// `InvalidConfig` would send an operator to debug their own setup for a bad
/// server payload
#[derive(Debug)]
pub enum SchemaCheckError {
    /// The envelope, or the snapshot body's `schemaVersion` field, is malformed
    Malformed(String),
    /// The snapshot's schema version is not the one this SDK build supports
    UnsupportedSchemaVersion { actual: u32, supported: u32 },
}

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
/// Returns `SchemaCheckError::UnsupportedSchemaVersion` when the version differs,
/// or `SchemaCheckError::Malformed` when the envelope or the snapshot's version
/// field cannot be parsed
pub fn check_envelope_schema_version(raw: &str) -> Result<&RawValue, SchemaCheckError> {
    let envelope: SnapshotEnvelope = serde_json::from_str(raw)
        .map_err(|e| SchemaCheckError::Malformed(format!("envelope parse failed: {e}")))?;

    let version: SnapshotVersionOnly =
        serde_json::from_str(envelope.snapshot.get()).map_err(|e| {
            SchemaCheckError::Malformed(format!(
                "snapshot body missing or malformed schemaVersion: {e}"
            ))
        })?;

    if version.schema_version != SUPPORTED_SCHEMA_VERSION {
        return Err(SchemaCheckError::UnsupportedSchemaVersion {
            actual: version.schema_version,
            supported: SUPPORTED_SCHEMA_VERSION,
        });
    }

    Ok(envelope.snapshot)
}

/// Intentional test-only surface, compiled into every build so integration tests
/// in the separate test crate can reach it (a `#[cfg(test)]` gate would not).
/// `#[doc(hidden)]`, not re-exported through the FFI, and its `panic!` sites only
/// fire on malformed test input, never on production paths
#[doc(hidden)]
pub mod test_support {
    use super::*;
    use std::collections::HashMap;

    /// Build an `IndexedSnapshot` directly so pipeline tests can seed flag
    /// fixtures without composing the full wire envelope
    pub fn snapshot_with_flags(flags: Vec<Flag>) -> IndexedSnapshot {
        let mut map = HashMap::new();
        for flag in flags {
            map.insert(flag.key.clone(), flag);
        }
        IndexedSnapshot {
            schema_version: 1,
            generated_at: String::new(),
            version: 1,
            environment: Default::default(),
            flags: map,
            segments: HashMap::new(),
        }
    }

    /// Build an `IndexedSnapshot` carrying a specific `version` and no flags so
    /// swap-path tests can assert version-driven lifecycle behavior
    pub fn snapshot_with_version(version: u64) -> IndexedSnapshot {
        Snapshot {
            schema_version: 1,
            generated_at: String::new(),
            version,
            environment: Default::default(),
            flags: vec![],
            segments: vec![],
        }
        .into()
    }

    /// Bool flag with no rules or prerequisites whose fallthrough deterministically
    /// resolves to `value` under any context. The `on` variation carries `true`
    /// and the `off` variation carries `false`, and the fallthrough points at
    /// whichever variation matches `value`
    pub fn bool_flag(key: &str, value: bool) -> Flag {
        let mut flag = bool_flag_with_prereqs(key, &[]);
        flag.fallthrough_variation = Some(if value { "on" } else { "off" }.to_string());
        flag
    }

    pub fn bool_flag_with_prereqs(key: &str, prereqs: &[(&str, &str)]) -> Flag {
        Flag {
            key: key.to_string(),
            r#type: FlagType::Bool,
            enabled: true,
            is_paused: false,
            variations: vec![
                Variation {
                    key: "on".to_string(),
                    value: VariationValue::Bool(true),
                    name: None,
                },
                Variation {
                    key: "off".to_string(),
                    value: VariationValue::Bool(false),
                    name: None,
                },
            ],
            off_variation: Some("off".to_string()),
            fallthrough_variation: Some("on".to_string()),
            targeting_rules: Vec::new(),
            prerequisites: prereqs
                .iter()
                .map(|(k, v)| Prerequisite {
                    flag_key: (*k).to_string(),
                    variation: (*v).to_string(),
                })
                .collect(),
            experiment: None,
        }
    }

    pub mod case_runner {
        use super::{bool_flag_with_prereqs, snapshot_with_flags};
        use crate::snapshot::IndexedSnapshot;
        use serde::Deserialize;
        use std::fs;
        use std::path::Path;

        #[derive(Debug, Deserialize)]
        pub struct PipelineCase {
            pub name: String,
            #[serde(default)]
            pub snapshot: Option<serde_json::Value>,
            pub snapshot_template: Option<String>,
            #[serde(default)]
            pub snapshot_args: serde_json::Value,
            pub flag_key: String,
            pub requested_type: String,
            pub expected_error_code: Option<String>,
            pub expected_variation: Option<String>,
            pub expected_reason: Option<String>,
        }

        #[derive(Debug, Deserialize)]
        struct Wrapper {
            pipeline_cases: Vec<PipelineCase>,
        }

        pub fn load_pipeline_cases(path: impl AsRef<Path>) -> Vec<PipelineCase> {
            let raw = fs::read_to_string(path).expect("cases.json must be readable");
            let wrapper: Wrapper = serde_json::from_str(&raw).expect("cases.json must parse");
            wrapper.pipeline_cases
        }

        /// Expand a case into the in-memory snapshot the pipeline evaluates. An
        /// explicit null `snapshot` models the not-ready provider and returns
        /// None. Every template builds an `IndexedSnapshot` directly
        pub fn expand_template(case: &PipelineCase) -> Option<IndexedSnapshot> {
            if matches!(case.snapshot.as_ref(), Some(v) if v.is_null()) {
                return None;
            }
            match case.snapshot_template.as_deref() {
                Some("empty") => Some(snapshot_with_flags(vec![])),
                Some("single_bool_flag") => Some(template_single_bool_flag(&case.snapshot_args)),
                Some("single_bool_flag_with_always_on_rule") => {
                    Some(template_single_bool_with_rule(&case.snapshot_args))
                }
                Some("dependent_with_gate") => {
                    Some(template_dependent_with_gate(&case.snapshot_args))
                }
                Some("two_flag_cycle") => Some(template_two_flag_cycle()),
                Some("chain_length") => Some(template_chain_length(&case.snapshot_args)),
                Some(other) => panic!("unknown snapshot_template: {other}"),
                None => None,
            }
        }

        fn str_arg<'a>(args: &'a serde_json::Value, key: &str, fallback: &'a str) -> &'a str {
            args.get(key).and_then(|v| v.as_str()).unwrap_or(fallback)
        }

        fn bool_arg(args: &serde_json::Value, key: &str, fallback: bool) -> bool {
            args.get(key).and_then(|v| v.as_bool()).unwrap_or(fallback)
        }

        fn template_single_bool_flag(args: &serde_json::Value) -> IndexedSnapshot {
            let key = str_arg(args, "key", "single");
            let mut flag = bool_flag_with_prereqs(key, &[]);
            flag.is_paused = bool_arg(args, "is_paused", false);
            flag.enabled = bool_arg(args, "enabled", true);
            if let Some(ft) = args.get("fallthrough") {
                flag.fallthrough_variation = if ft.is_null() {
                    None
                } else {
                    Some(ft.as_str().unwrap_or("on").to_string())
                };
            }
            snapshot_with_flags(vec![flag])
        }

        fn template_single_bool_with_rule(args: &serde_json::Value) -> IndexedSnapshot {
            use crate::snapshot::{Condition, Coverage, Rollout, TargetingRule};
            let key = str_arg(args, "key", "targeted");
            let variation = str_arg(args, "rule_variation", "on").to_string();
            let mut flag = bool_flag_with_prereqs(key, &[]);
            flag.targeting_rules = vec![TargetingRule {
                rule_id: "00000000-0000-0000-0000-00000000aaaa".to_string(),
                condition: Condition::Always,
                coverage: Coverage(10_000),
                rollout: Rollout::Variation { variation },
                description: None,
            }];
            snapshot_with_flags(vec![flag])
        }

        fn template_dependent_with_gate(args: &serde_json::Value) -> IndexedSnapshot {
            let required = str_arg(args, "required", "on").to_string();
            snapshot_with_flags(vec![
                bool_flag_with_prereqs("dependent", &[("gate", &required)]),
                bool_flag_with_prereqs("gate", &[]),
            ])
        }

        fn template_two_flag_cycle() -> IndexedSnapshot {
            snapshot_with_flags(vec![
                bool_flag_with_prereqs("a", &[("b", "on")]),
                bool_flag_with_prereqs("b", &[("a", "on")]),
            ])
        }

        fn template_chain_length(args: &serde_json::Value) -> IndexedSnapshot {
            let length = args.get("length").and_then(|v| v.as_u64()).unwrap_or(5) as usize;
            let mut flags = Vec::with_capacity(length + 1);
            for i in 0..length {
                let key = format!("f{i}");
                let next = format!("f{}", i + 1);
                flags.push(bool_flag_with_prereqs(&key, &[(&next, "on")]));
            }
            flags.push(bool_flag_with_prereqs(&format!("f{length}"), &[]));
            snapshot_with_flags(flags)
        }
    }
}
