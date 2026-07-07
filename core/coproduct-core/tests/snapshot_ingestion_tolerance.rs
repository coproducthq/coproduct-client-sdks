use coproduct_core::context::EvaluationContext;
use coproduct_core::error::EvaluationErrorCode;
use coproduct_core::eval::evaluate_for_observer;
use coproduct_core::pipeline::{RequestedType, evaluate};
use coproduct_core::snapshot::{FlagType, IndexedSnapshot, Rollout, Snapshot};

// One unparseable flag must never wedge the whole snapshot. The top-level
// envelope stays strict, but individual flags are decoded leniently: an unknown
// type is retained and fails closed, a malformed body is dropped, and a bad
// weight is coalesced, while the rest of the snapshot keeps applying.

const GOOD_BOOL: &str = r#"{"key":"b","type":"BOOL","enabled":true,"isPaused":false,
  "variations":[{"key":"on","value":true},{"key":"off","value":false}],
  "offVariation":"off","fallthroughVariation":"on",
  "targetingRules":[],"prerequisites":[],"experiment":null}"#;

fn snapshot_json(flags_array: &str) -> String {
    format!(
        r#"{{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",
        "environment":{{"slug":"e","projectKey":"p"}},"flags":{flags_array},"segments":[]}}"#
    )
}

fn parse(flags_array: &str) -> IndexedSnapshot {
    let snapshot: Snapshot =
        serde_json::from_str(&snapshot_json(flags_array)).expect("snapshot parses");
    IndexedSnapshot::from(snapshot)
}

#[test]
fn unknown_flag_type_is_retained_and_fails_closed() {
    let flags =
        format!(r#"[{GOOD_BOOL},{{"key":"x","type":"DATETIME","enabled":true,"variations":[]}}]"#);
    let snapshot = parse(&flags);
    let ctx = EvaluationContext::with_targeting_key("u1");

    // The unknown type does not reject the snapshot: both flags are present
    assert_eq!(snapshot.flags.len(), 2);
    assert_eq!(snapshot.flags.get("x").unwrap().r#type, FlagType::Unknown);

    // The good flag still applies
    let good = evaluate(Some(&snapshot), "b", RequestedType::Bool, &ctx);
    assert_eq!(good.variation_key.as_deref(), Some("on"));
    assert_eq!(good.error_code, None);

    // The unknown flag fails closed: a getter returns the default with a type
    // mismatch, and the observer path omits it entirely
    let unknown = evaluate(Some(&snapshot), "x", RequestedType::Bool, &ctx);
    assert_eq!(unknown.error_code, Some(EvaluationErrorCode::TypeMismatch));
    assert!(evaluate_for_observer(&snapshot, "x", &ctx).is_none());
}

#[test]
fn a_structurally_malformed_flag_is_dropped_and_the_rest_apply() {
    // `variations` is a string, not an array, so this flag cannot parse
    let flags = format!(r#"[{GOOD_BOOL},{{"key":"bad","type":"BOOL","variations":"oops"}}]"#);
    let snapshot = parse(&flags);

    assert_eq!(snapshot.flags.len(), 1, "the malformed flag is dropped");
    assert!(snapshot.flags.contains_key("b"));
    assert!(!snapshot.flags.contains_key("bad"));
}

#[test]
fn malformed_weights_coalesce_and_do_not_reject_the_snapshot() {
    let flags = r#"[{"key":"w","type":"BOOL","enabled":true,
      "variations":[{"key":"on","value":true},{"key":"off","value":false}],
      "offVariation":"off","fallthroughVariation":"off",
      "targetingRules":[{"rule_id":"11111111-1111-1111-1111-111111111111",
        "condition":{"type":"always"},"coverage":10000,
        "rollout":{"type":"weights","weights":[
          {"variation_key":"on","percentage":100.5},
          {"variation_key":"off","percentage":-5}]}}],
      "prerequisites":[],"experiment":null}]"#;
    let snapshot = parse(flags);

    let flag = snapshot.flags.get("w").expect("the weighted flag survives");
    match &flag.targeting_rules[0].rollout {
        Rollout::Weights { weights } => {
            assert_eq!(
                weights[0].percentage, 100,
                "100.5 truncates and clamps to 100"
            );
            assert_eq!(weights[1].percentage, 0, "-5 clamps to 0");
        }
        other => panic!("expected weights, got {other:?}"),
    }
}

#[test]
fn a_deeply_nested_flag_is_dropped_and_the_rest_apply() {
    // A JSON flag whose variation value nests past serde_json's default 128
    // recursion limit. Materializing the array up front would fail on this single
    // entry and reject the whole snapshot, losing the valid sibling flag. Per
    // entry raw capture isolates the failure to this one flag
    let depth = 300;
    let deep_value = format!("{}{}", "[".repeat(depth), "]".repeat(depth));
    let deep_flag = format!(
        r#"{{"key":"deep","type":"JSON","enabled":true,"isPaused":false,
        "variations":[{{"key":"v","value":{deep_value}}}],
        "offVariation":"v","fallthroughVariation":"v",
        "targetingRules":[],"prerequisites":[],"experiment":null}}"#
    );
    let flags = format!(r#"[{GOOD_BOOL},{deep_flag}]"#);
    let snapshot = parse(&flags);

    assert_eq!(snapshot.flags.len(), 1, "the deeply nested flag is dropped");
    assert!(snapshot.flags.contains_key("b"));
    assert!(!snapshot.flags.contains_key("deep"));
}

#[test]
fn a_malformed_segment_is_dropped_and_valid_segments_apply() {
    // Segment ingestion is tolerant the same way flag ingestion is. One segment
    // whose `rules` is a string cannot parse and is dropped, while a valid segment
    // referenced by a flag is retained and the snapshot still applies
    let segments = r#"[
      {"key":"pro","name":"Pro","rules":[{"attribute":"plan","operator":"in","values":["pro"]}]},
      {"key":"bad","rules":"oops"}]"#;
    let json = format!(
        r#"{{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",
        "environment":{{"slug":"e","projectKey":"p"}},"flags":[{GOOD_BOOL}],"segments":{segments}}}"#
    );
    let snapshot: IndexedSnapshot = serde_json::from_str::<Snapshot>(&json)
        .expect("snapshot parses")
        .into();

    assert_eq!(
        snapshot.segments.len(),
        1,
        "the malformed segment is dropped"
    );
    assert!(snapshot.segments.contains_key("pro"));
    assert!(!snapshot.segments.contains_key("bad"));
    assert!(
        snapshot.flags.contains_key("b"),
        "the valid flag still applies"
    );
}

#[test]
fn present_null_flags_is_treated_as_empty_and_segments_survive() {
    // An explicit `"flags": null` must not reject the whole snapshot the way a
    // non-array value does; it is treated as an empty list, so a valid segment
    // alongside it still applies
    let json = r#"{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",
      "environment":{"slug":"e","projectKey":"p"},"flags":null,
      "segments":[{"key":"pro","name":"Pro","rules":[]}]}"#;
    let snapshot: IndexedSnapshot = serde_json::from_str::<Snapshot>(json)
        .expect("null flags does not reject the snapshot")
        .into();
    assert!(snapshot.flags.is_empty(), "null flags parses as empty");
    assert_eq!(
        snapshot.segments.len(),
        1,
        "the valid segment still applies"
    );
}

#[test]
fn duplicate_flag_keys_keep_the_last_entry() {
    // The wire shape is a list, so two flags can share a key. The last wins in the
    // indexed map, and the drop is warned rather than silent
    let flags = format!(
        r#"[{GOOD_BOOL},{{"key":"b","type":"BOOL","enabled":false,"isPaused":false,
        "variations":[{{"key":"on","value":true}},{{"key":"off","value":false}}],
        "offVariation":"off","fallthroughVariation":"off",
        "targetingRules":[],"prerequisites":[],"experiment":null}}]"#
    );
    let snapshot = parse(&flags);
    assert_eq!(
        snapshot.flags.len(),
        1,
        "the duplicate key collapses to one entry"
    );
    assert!(
        !snapshot.flags.get("b").unwrap().enabled,
        "the last entry, which is disabled, wins"
    );
}

#[test]
fn a_malformed_top_level_snapshot_is_still_rejected() {
    // `flags` is an object, not an array
    let non_array_flags = snapshot_json("{}");
    assert!(
        serde_json::from_str::<Snapshot>(&non_array_flags).is_err(),
        "a non-array flags field is rejected"
    );

    // A missing required `version` is rejected
    let missing_version = r#"{"schemaVersion":1,"environment":{"slug":"e","projectKey":"p"},"flags":[],"segments":[]}"#;
    assert!(
        serde_json::from_str::<Snapshot>(missing_version).is_err(),
        "a missing version is rejected"
    );
}
