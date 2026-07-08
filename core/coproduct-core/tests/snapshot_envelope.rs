use coproduct_core::snapshot::{
    Condition, Coverage, FlagType, Rollout, SdkContext, Segment, Snapshot,
    check_envelope_schema_version,
};

const WIRE: &str = r#"{
    "snapshot": {
        "schemaVersion": 1,
        "generatedAt": "2026-05-26T10:32:14Z",
        "version": 47,
        "environment": { "slug": "production", "projectKey": "my-app" },
        "flags": [
            {
                "key": "new-checkout",
                "type": "BOOL",
                "enabled": true,
                "isPaused": false,
                "variations": [
                    { "key": "on", "value": true },
                    { "key": "off", "value": false }
                ],
                "offVariation": "off",
                "fallthroughVariation": "off",
                "targetingRules": [
                    {
                        "rule_id": "11111111-2222-4333-8444-555555555555",
                        "condition": { "type": "always" },
                        "coverage": 10000,
                        "rollout": { "type": "variation", "variation": "on" }
                    }
                ],
                "prerequisites": [],
                "experiment": null
            }
        ],
        "segments": [
            {
                "key": "internal_users",
                "name": "Internal Users",
                "rules": [
                    { "attribute": "email", "operator": "ends_with", "values": ["@coproduct.app"] }
                ]
            }
        ]
    },
    "sdkContext": {
        "country": "US",
        "continent": "NA",
        "regionCode": "CA",
        "city": "San Francisco",
        "timezone": "America/Los_Angeles"
    }
}"#;

#[test]
fn snapshot_envelope_round_trips() {
    let envelope: coproduct_core::snapshot::SnapshotEnvelope = serde_json::from_str(WIRE).unwrap();
    let snap: Snapshot = serde_json::from_str(envelope.snapshot.get()).unwrap();
    assert_eq!(snap.schema_version, 1);
    assert_eq!(snap.generated_at, "2026-05-26T10:32:14Z");
    assert_eq!(snap.version, 47);
    assert_eq!(snap.flags.len(), 1);
    assert_eq!(snap.flags[0].key, "new-checkout");
    assert_eq!(snap.flags[0].r#type, FlagType::Bool);
    assert_eq!(snap.flags[0].targeting_rules.len(), 1);
    assert_eq!(snap.flags[0].targeting_rules[0].coverage, Coverage(10000));
    assert_eq!(
        snap.flags[0].targeting_rules[0].condition,
        Condition::Always
    );
    assert_eq!(
        snap.flags[0].targeting_rules[0].rollout,
        Rollout::Variation {
            variation: "on".to_string()
        }
    );

    let sdk_ctx_raw = envelope.sdk_context.expect("sdkContext present");
    let sdk_ctx: SdkContext = serde_json::from_str(sdk_ctx_raw.get()).unwrap();
    assert_eq!(sdk_ctx.country.as_deref(), Some("US"));
    assert_eq!(sdk_ctx.continent.as_deref(), Some("NA"));
    assert_eq!(sdk_ctx.region_code.as_deref(), Some("CA"));
    assert_eq!(sdk_ctx.city.as_deref(), Some("San Francisco"));
    assert_eq!(sdk_ctx.timezone, "America/Los_Angeles");

    let seg = &snap.segments[0];
    assert_eq!(seg.key, "internal_users");
    assert_eq!(seg.name, "Internal Users");
    assert_eq!(seg.rules.len(), 1);
}

#[test]
fn snapshot_tolerates_missing_optional_sections() {
    let minimal = r#"{ "snapshot": { "schemaVersion": 1, "version": 1 } }"#;
    let envelope: coproduct_core::snapshot::SnapshotEnvelope =
        serde_json::from_str(minimal).unwrap();
    let snap: Snapshot = serde_json::from_str(envelope.snapshot.get()).unwrap();
    assert_eq!(snap.version, 1);
    assert!(snap.flags.is_empty());
    assert!(snap.segments.is_empty());
    assert!(envelope.sdk_context.is_none());
    assert_eq!(snap.generated_at, "");
}

#[test]
fn sdk_context_partial_fields_tolerated() {
    let wire = r#"{ "country": "US", "timezone": "America/Los_Angeles" }"#;
    let ctx: SdkContext = serde_json::from_str(wire).unwrap();
    assert_eq!(ctx.country.as_deref(), Some("US"));
    assert!(ctx.continent.is_none());
    assert!(ctx.region_code.is_none());
    assert!(ctx.city.is_none());
    assert_eq!(ctx.timezone, "America/Los_Angeles");
}

#[test]
fn sdk_context_geo_values_are_normalized_like_developer_values() {
    // The edge may send lowercase geo codes. They are normalized (upper-cased) the
    // same way a developer-supplied value would be, so a rule matches identically
    // whichever layer supplied the value
    let ctx: SdkContext = serde_json::from_str(
        r#"{ "country": "us", "continent": "na", "regionCode": "ca", "timezone": "UTC" }"#,
    )
    .unwrap();
    let map = coproduct_core::context::sdk_context_to_attribute_map(ctx);
    use coproduct_core::context::AttributeValue;
    assert_eq!(
        map.get("country"),
        Some(&AttributeValue::String("US".to_string()))
    );
    assert_eq!(
        map.get("region_code"),
        Some(&AttributeValue::String("CA".to_string()))
    );
}

#[test]
fn sdk_context_defaults_missing_timezone_to_utc() {
    // The server may omit timezone. Without a default this fails the whole
    // sdkContext parse, and the poll and cache-prewarm paths swallow that with
    // `.ok()` and drop every geo attribute, so a country-targeted flag would
    // evaluate against no country at all
    let wire = r#"{ "country": "US" }"#;
    let ctx: SdkContext = serde_json::from_str(wire).expect("a missing timezone still parses");
    assert_eq!(ctx.country.as_deref(), Some("US"));
    assert_eq!(ctx.timezone, "UTC");
}

#[test]
fn sdk_context_accepts_camelcase_region_code() {
    let wire = r#"{ "regionCode": "CA", "timezone": "UTC" }"#;
    let ctx: SdkContext = serde_json::from_str(wire).unwrap();
    assert_eq!(ctx.region_code.as_deref(), Some("CA"));
}

#[test]
fn segment_tolerates_missing_name_and_rules() {
    let s: Segment = serde_json::from_str(r#"{ "key": "x" }"#).unwrap();
    assert_eq!(s.key, "x");
    assert_eq!(s.name, "");
    assert!(s.rules.is_empty());
}

#[test]
fn schema_version_fence_accepts_snapshot_envelope_fixture() {
    let snapshot = check_envelope_schema_version(WIRE).unwrap();
    let snap: Snapshot = serde_json::from_str(snapshot.get()).unwrap();
    assert_eq!(snap.schema_version, 1);
    assert_eq!(snap.version, 47);
}
