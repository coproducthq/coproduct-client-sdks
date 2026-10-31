//! Segment + top-level Snapshot envelope

use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

use super::flag::Flag;
use super::rule::Operator;

/// Deserialize a snapshot array element-by-element so one unparseable entry is
/// dropped with a warning instead of failing the whole snapshot. A present-but-
/// null field is treated as empty, so an explicit `"flags": null` does not reject
/// the snapshot the way an omitted field would not. A non-null, non-array value
/// still fails, which keeps the envelope strict while an individual flag or
/// segment fails closed. A dropped flag is absent, so its getters return the
/// caller default, and a newer server can ship an additive change to one flag
/// without freezing updates for the rest
fn deserialize_tolerant_vec<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: serde::de::DeserializeOwned,
{
    // Capture each array element as a raw slice before parsing it. Materializing
    // the array as `Vec<serde_json::Value>` would descend into every element up
    // front, so a single entry nested past the deserializer's recursion limit
    // would fail the whole array and wedge the snapshot. Raw capture records an
    // element's bytes without descending, so the limit is only reached, and only
    // isolated, when the offending entry is parsed on its own below. The outer
    // `Option` maps a present `null` to an empty list rather than a hard error
    let raw_items = Option::<Vec<Box<serde_json::value::RawValue>>>::deserialize(deserializer)?
        .unwrap_or_default();
    let mut items = Vec::with_capacity(raw_items.len());
    for raw in raw_items {
        match serde_json::from_str::<T>(raw.get()) {
            Ok(item) => items.push(item),
            Err(error) => tracing::warn!(
                key = entry_key(&raw).as_deref().unwrap_or("<unknown>"),
                %error,
                "dropping unparseable snapshot entry"
            ),
        }
    }
    Ok(items)
}

// Best-effort read of an entry's `key` for the drop warning. Returns `None` when
// the entry is too malformed, or too deeply nested, to read the key at all, in
// which case the warning names the entry as unknown
fn entry_key(raw: &serde_json::value::RawValue) -> Option<String> {
    #[derive(Deserialize)]
    struct KeyOnly {
        #[serde(default)]
        key: Option<String>,
    }
    serde_json::from_str::<KeyOnly>(raw.get()).ok()?.key
}

// serde `deserialize_with` cannot infer the element type from a generic path, so
// each field points at a monomorphic wrapper over the shared tolerant decoder
fn deserialize_tolerant_flags<'de, D>(deserializer: D) -> Result<Vec<Flag>, D::Error>
where
    D: Deserializer<'de>,
{
    deserialize_tolerant_vec(deserializer)
}

fn deserialize_tolerant_segments<'de, D>(deserializer: D) -> Result<Vec<Segment>, D::Error>
where
    D: Deserializer<'de>,
{
    deserialize_tolerant_vec(deserializer)
}

fn deserialize_tolerant_onboarding_flows<'de, D>(
    deserializer: D,
) -> Result<Vec<OnboardingFlowEntry>, D::Error>
where
    D: Deserializer<'de>,
{
    deserialize_tolerant_vec(deserializer)
}

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

/// One rule inside a `Segment`. Segments resolve with OR semantics across their
/// rules. Coverage and rollout do not apply at the segment level (membership is
/// binary).
///
/// The common form is a flat attribute-operator-values triple matching the
/// platform's segment-rule wire schema (`country equals US`, `city in [...]`).
/// `Geofence` is a typed circular geo-fence on the device's `{lat,lng}` point,
/// authored the same way a country or city rule is but carrying structured
/// center/radius numbers rather than a packed string. The `Unknown` arm catches
/// a forward-incompatible rule shape so it fails the flag closed (RULE_CIRCUIT_
/// BREAK) rather than aborting the snapshot parse, matching `Condition`
#[derive(Debug, Clone, PartialEq)]
pub enum SegmentRule {
    Attribute {
        attribute: String,
        operator: Operator,
        values: Vec<String>,
    },
    Geofence {
        attribute: String,
        center_lat: f64,
        center_lng: f64,
        radius_m: f64,
    },
    Unknown {
        tag: String,
    },
}

impl Serialize for SegmentRule {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match self {
            // The attribute form carries no `type` tag, matching the existing
            // platform wire schema so legacy rules round-trip unchanged
            SegmentRule::Attribute {
                attribute,
                operator,
                values,
            } => {
                let mut map = serializer.serialize_map(Some(3))?;
                map.serialize_entry("attribute", attribute)?;
                map.serialize_entry("operator", operator)?;
                map.serialize_entry("values", values)?;
                map.end()
            }
            SegmentRule::Geofence {
                attribute,
                center_lat,
                center_lng,
                radius_m,
            } => {
                let mut map = serializer.serialize_map(Some(4))?;
                map.serialize_entry("type", "geofence")?;
                map.serialize_entry("attribute", attribute)?;
                map.serialize_entry(
                    "center",
                    &serde_json::json!({ "lat": center_lat, "lng": center_lng }),
                )?;
                map.serialize_entry("radius_m", radius_m)?;
                map.end()
            }
            SegmentRule::Unknown { tag } => {
                let mut map = serializer.serialize_map(Some(1))?;
                map.serialize_entry("type", tag)?;
                map.end()
            }
        }
    }
}

impl<'de> Deserialize<'de> for SegmentRule {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = Value::deserialize(deserializer)?;
        Ok(Self::from_value(raw))
    }
}

impl SegmentRule {
    /// Tolerant decode mirroring `Condition::from_value`. An attribute rule has no
    /// `type` tag (or `type: "attribute"`); a `geofence` rule carries a typed
    /// center and radius; anything else, or a structurally invalid body, becomes
    /// `Unknown { tag }` so the referencing flag fails closed
    fn from_value(raw: Value) -> SegmentRule {
        let obj = match raw.as_object() {
            Some(o) => o,
            None => {
                return SegmentRule::Unknown {
                    tag: "non_object".into(),
                };
            }
        };
        let tag = obj.get("type").and_then(|v| v.as_str());
        match tag {
            Some("geofence") => {
                let attribute = obj.get("attribute").and_then(|v| v.as_str());
                let center = obj.get("center").and_then(|v| v.as_object());
                let center_lat = center.and_then(|c| c.get("lat")).and_then(|v| v.as_f64());
                let center_lng = center.and_then(|c| c.get("lng")).and_then(|v| v.as_f64());
                let radius_m = obj.get("radius_m").and_then(|v| v.as_f64());
                match (attribute, center_lat, center_lng, radius_m) {
                    (Some(attribute), Some(lat), Some(lng), Some(radius))
                        if lat.is_finite() && lng.is_finite() && radius.is_finite() =>
                    {
                        SegmentRule::Geofence {
                            attribute: attribute.to_string(),
                            center_lat: lat,
                            center_lng: lng,
                            radius_m: radius,
                        }
                    }
                    _ => SegmentRule::Unknown {
                        tag: "geofence".into(),
                    },
                }
            }
            None | Some("attribute") => {
                let attribute = obj.get("attribute").and_then(|v| v.as_str());
                let operator = obj
                    .get("operator")
                    .and_then(|v| serde_json::from_value::<Operator>(v.clone()).ok());
                let values = match obj.get("values") {
                    None => Some(Vec::new()),
                    Some(v) => values_as_string_vec(v),
                };
                match (attribute, operator, values) {
                    (Some(attribute), Some(operator), Some(values)) => SegmentRule::Attribute {
                        attribute: attribute.to_string(),
                        operator,
                        values,
                    },
                    _ => SegmentRule::Unknown {
                        tag: "attribute".into(),
                    },
                }
            }
            Some(other) => SegmentRule::Unknown {
                tag: other.to_string(),
            },
        }
    }
}

/// Parse a segment rule's wire `values` field. Returns `None` when the value is
/// not an array of strings, routing the rule to `Unknown` so a malformed RHS
/// fails closed rather than silently repairing
fn values_as_string_vec(v: &Value) -> Option<Vec<String>> {
    let arr = v.as_array()?;
    let mut out = Vec::with_capacity(arr.len());
    for item in arr {
        out.push(item.as_str()?.to_string());
    }
    Some(out)
}

/// One resolved onboarding flow's content, as it reaches a device: the
/// flowId a pointer flag's variation resolves to, the graph for whichever
/// version this environment is pinned to (or HEAD, unpinned), and that
/// version number. `graph` stays opaque JSON here rather than a typed
/// screen/transition graph -- the core has no business logic over an
/// onboarding flow's content, it only carries it from the snapshot to
/// whichever host wrapper renders it (see coproduct_onboarding's own typed
/// `OnboardingFlowGraph` on the Dart/TS side)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OnboardingFlowEntry {
    #[serde(rename = "flowId")]
    pub flow_id: String,
    pub graph: serde_json::Value,
    pub version: u64,
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
    #[serde(default, deserialize_with = "deserialize_tolerant_flags")]
    pub flags: Vec<Flag>,
    #[serde(default, deserialize_with = "deserialize_tolerant_segments")]
    pub segments: Vec<Segment>,
    #[serde(
        rename = "onboardingFlows",
        default,
        deserialize_with = "deserialize_tolerant_onboarding_flows"
    )]
    pub onboarding_flows: Vec<OnboardingFlowEntry>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnvironmentMetadata {
    #[serde(default)]
    pub slug: String,
    #[serde(rename = "projectKey", default)]
    pub project_key: String,
}

/// Flat read-only projection of the held snapshot for host wrappers. Carries
/// only the scalar facts a host UI surfaces about the loaded configuration
/// without exposing the full flag map across a binding boundary
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SnapshotView {
    pub version: u64,
    pub flag_count: u32,
    pub environment: String,
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
    pub onboarding_flows: std::collections::HashMap<String, OnboardingFlowEntry>,
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
            onboarding_flows: self.onboarding_flows.values().cloned().collect(),
        }
    }
}

/// Re-key a wire vec into a lookup map, warning when two entries share a key. The
/// wire shape is a list, so a duplicate key is possible; the last entry wins, and
/// the warning names the collision rather than dropping data silently
fn index_by_key<T>(
    items: Vec<T>,
    key_of: impl Fn(&T) -> String,
    kind: &str,
) -> std::collections::HashMap<String, T> {
    let mut map = std::collections::HashMap::with_capacity(items.len());
    for item in items {
        let key = key_of(&item);
        if map.insert(key.clone(), item).is_some() {
            tracing::warn!(key = %key, kind, "duplicate snapshot entry key, keeping the last");
        }
    }
    map
}

impl From<Snapshot> for IndexedSnapshot {
    fn from(wire: Snapshot) -> Self {
        let flags = index_by_key(wire.flags, |f| f.key.clone(), "flag");
        let segments = index_by_key(wire.segments, |s| s.key.clone(), "segment");
        let onboarding_flows = index_by_key(
            wire.onboarding_flows,
            |f| f.flow_id.clone(),
            "onboarding_flow",
        );
        Self {
            schema_version: wire.schema_version,
            generated_at: wire.generated_at,
            version: wire.version,
            environment: wire.environment,
            flags,
            segments,
            onboarding_flows,
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
    /// First-level region code: the bare ISO 3166-2 subdivision part without a
    /// country prefix (e.g. `"TX"`), camelCase on the wire
    #[serde(default, rename = "regionCode")]
    pub region_code: Option<String>,
    #[serde(default)]
    pub city: Option<String>,
    /// IANA timezone name. Defaults to `"UTC"` when the server omits it, so a
    /// missing timezone does not fail the whole `sdkContext` parse and silently
    /// drop the sibling geo attributes a flag's targeting may reference
    #[serde(default = "default_timezone")]
    pub timezone: String,
}

fn default_timezone() -> String {
    "UTC".to_string()
}
