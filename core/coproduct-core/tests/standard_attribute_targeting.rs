//! End-to-end conformance for the platform's standard targeting attributes.
//!
//! The platform offers a rule author a list of conventional standard attribute
//! names (identity, edge-derived geo, device-derived, SDK-persisted). These
//! tests pin the consumer half of that contract: a rule authored against a
//! standard name matches the value the corresponding layer supplies, under the
//! exact snake_case key the platform uses

use std::collections::HashMap;

use coproduct_core::context::{AttributeValue, EvaluationContext, sdk_context_to_attribute_map};
use coproduct_core::identity_state::IdentityState;
use coproduct_core::rule_walker::{RuleWalkResult, walk_rules};
use coproduct_core::snapshot::{Flag, SdkContext, Segment};

fn flag_with_rule(condition_json: serde_json::Value) -> Flag {
    serde_json::from_value(serde_json::json!({
        "key": "f",
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
                "rule_id": "00000000-0000-4000-8000-0000000000aa",
                "condition": condition_json,
                "coverage": 10000,
                "rollout": { "type": "variation", "variation": "on" }
            }
        ],
        "prerequisites": [],
        "experiment": null
    }))
    .expect("flag fixture parses")
}

fn attribute_condition(attribute: &str, operator: &str, values: &[&str]) -> serde_json::Value {
    serde_json::json!({
        "type": "attribute",
        "attribute": attribute,
        "operator": operator,
        "values": values,
    })
}

fn rule_matches(ctx: &EvaluationContext, condition: serde_json::Value) -> bool {
    let flag = flag_with_rule(condition);
    let segments: HashMap<String, Segment> = HashMap::new();
    matches!(
        walk_rules(&flag, ctx, &segments),
        RuleWalkResult::Match { .. }
    )
}

/// Context holding the edge-derived attributes the way the client does after a
/// snapshot fetch: the wire `sdkContext` projected through
/// `sdk_context_to_attribute_map` into the lowest-precedence layer
fn context_with_edge_attributes(wire_sdk_context: &str) -> EvaluationContext {
    let sdk_ctx: SdkContext = serde_json::from_str(wire_sdk_context).expect("sdkContext parses");
    let mut ctx = EvaluationContext::with_targeting_key("user-1");
    for (name, value) in sdk_context_to_attribute_map(sdk_ctx) {
        ctx.set_sdk_context(&name, value);
    }
    ctx
}

#[test]
fn edge_attributes_match_rules_under_their_standard_names() {
    // The server sends regionCode as the bare first-level subdivision code
    // (e.g. "TX"), camelCase. The core stores it under the snake_case standard
    // name region_code a rule is authored with
    let ctx = context_with_edge_attributes(
        r#"{ "country": "US", "continent": "NA", "regionCode": "TX",
             "city": "Austin", "timezone": "America/Chicago" }"#,
    );
    for (attribute, expected) in [
        ("country", "US"),
        ("continent", "NA"),
        ("region_code", "TX"),
        ("city", "Austin"),
        ("timezone", "America/Chicago"),
    ] {
        assert!(
            rule_matches(&ctx, attribute_condition(attribute, "equals", &[expected])),
            "rule on {attribute} should match {expected}"
        );
    }
}

#[test]
fn geo_codes_match_case_insensitively_through_normalization() {
    // The core uppercases country, continent, and region_code from any layer, so
    // a rule authored with the uppercase ISO form matches even when the wire
    // carried lowercase
    let ctx = context_with_edge_attributes(
        r#"{ "country": "us", "continent": "na", "regionCode": "tx", "timezone": "UTC" }"#,
    );
    assert!(rule_matches(
        &ctx,
        attribute_condition("country", "equals", &["US"])
    ));
    assert!(rule_matches(
        &ctx,
        attribute_condition("continent", "equals", &["NA"])
    ));
    assert!(rule_matches(
        &ctx,
        attribute_condition("region_code", "equals", &["TX"])
    ));
    // A rule authored lowercase never matches the normalized context value. The
    // platform stores rule values verbatim, so authoring owns the uppercase form
    assert!(!rule_matches(
        &ctx,
        attribute_condition("country", "equals", &["us"])
    ));
}

#[test]
fn city_is_not_normalized_and_matches_exact_server_casing() {
    let ctx = context_with_edge_attributes(r#"{ "city": "Austin", "timezone": "UTC" }"#);
    assert!(rule_matches(
        &ctx,
        attribute_condition("city", "equals", &["Austin"])
    ));
    assert!(!rule_matches(
        &ctx,
        attribute_condition("city", "equals", &["austin"])
    ));
}

#[test]
fn timezone_defaults_to_utc_when_the_server_omits_it() {
    let ctx = context_with_edge_attributes(r#"{ "country": "US" }"#);
    assert!(rule_matches(
        &ctx,
        attribute_condition("timezone", "equals", &["UTC"])
    ));
}

#[test]
fn absent_edge_attributes_are_not_set_rather_than_null() {
    // The server omits nullable geo fields it cannot derive. The projection
    // leaves them out of the map so is_not_set sees never-set, and equality
    // rules on them fall through instead of matching
    let ctx = context_with_edge_attributes(r#"{ "timezone": "UTC" }"#);
    assert!(rule_matches(
        &ctx,
        attribute_condition("city", "is_not_set", &[])
    ));
    assert!(!rule_matches(
        &ctx,
        attribute_condition("city", "equals", &["Austin"])
    ));
}

#[test]
fn user_id_rules_match_the_targeting_key_identity() {
    let mut identity = IdentityState::new_anonymous("anon-1".to_string());
    identity
        .identify("user-42".to_string(), HashMap::new(), false)
        .expect("identify succeeds");
    let ctx = identity.context();
    assert!(rule_matches(
        ctx,
        attribute_condition("user_id", "equals", &["user-42"])
    ));
}

#[test]
fn email_is_an_ordinary_developer_attribute_set_via_identify() {
    let mut identity = IdentityState::new_anonymous("anon-1".to_string());
    identity
        .identify(
            "user-42".to_string(),
            HashMap::from([(
                "email".to_string(),
                AttributeValue::String("dev@coproduct.app".to_string()),
            )]),
            false,
        )
        .expect("identify succeeds");
    let ctx = identity.context();
    assert!(rule_matches(
        ctx,
        attribute_condition("email", "ends_with", &["@coproduct.app"])
    ));
}

#[test]
fn custom_attributes_outside_the_standard_list_are_first_class() {
    // The standard-attribute list is authoring guidance. Evaluation never gates
    // on it, so a custom attribute targets exactly like a standard one
    let mut identity = IdentityState::new_anonymous("anon-1".to_string());
    identity
        .identify(
            "user-42".to_string(),
            HashMap::from([(
                "plan_tier".to_string(),
                AttributeValue::String("enterprise".to_string()),
            )]),
            false,
        )
        .expect("identify succeeds");
    let ctx = identity.context();
    assert!(rule_matches(
        ctx,
        attribute_condition("plan_tier", "equals", &["enterprise"])
    ));
}

#[test]
fn session_count_supplied_as_a_number_compares_numerically() {
    let mut ctx = EvaluationContext::with_targeting_key("user-1");
    ctx.set_developer("session_count", AttributeValue::Number(7.0));
    assert!(rule_matches(
        &ctx,
        attribute_condition("session_count", "gt", &["5"])
    ));
    assert!(!rule_matches(
        &ctx,
        attribute_condition("session_count", "gt", &["7"])
    ));
}

#[test]
fn app_build_integer_shaped_string_compares_numerically() {
    // app_build is an opaque string at the context level (iOS CFBundleVersion,
    // Android versionCode rendered as a string). The numeric operators parse an
    // integer-shaped string so a rule like app_build > 40 works against "42"
    let mut ctx = EvaluationContext::with_targeting_key("user-1");
    ctx.set_developer("app_build", AttributeValue::String("42".to_string()));
    assert!(rule_matches(
        &ctx,
        attribute_condition("app_build", "gt", &["40"])
    ));
    assert!(!rule_matches(
        &ctx,
        attribute_condition("app_build", "gt", &["42"])
    ));
    assert!(rule_matches(
        &ctx,
        attribute_condition("app_build", "equals", &["42"])
    ));
}

#[test]
fn app_build_non_numeric_string_never_matches_numeric_rules() {
    let mut ctx = EvaluationContext::with_targeting_key("user-1");
    ctx.set_developer("app_build", AttributeValue::String("1.0.42".to_string()));
    // A dotted iOS CFBundleVersion with two periods is not numeric. The
    // comparison is indeterminate and the rule falls through
    assert!(!rule_matches(
        &ctx,
        attribute_condition("app_build", "gt", &["40"])
    ));
}

#[test]
fn version_attributes_canonicalize_so_authored_rules_match() {
    // Both sides of a version comparison go through the same cleanup: the
    // platform canonicalizes rule values to three components on write, and the
    // context write path canonicalizes version-shaped values the same way. A
    // device-reported "17.4" therefore matches rules authored against 17.4
    // through the semver operators and equality alike
    let mut identity = IdentityState::new_anonymous("anon-1".to_string());
    identity
        .identify(
            "user-42".to_string(),
            HashMap::from([(
                "os_version".to_string(),
                AttributeValue::String("17.4".to_string()),
            )]),
            false,
        )
        .expect("identify succeeds");
    let ctx = identity.context();
    assert!(rule_matches(
        ctx,
        attribute_condition("os_version", "sem_ver_gte", &["17.0.0"])
    ));
    assert!(rule_matches(
        ctx,
        attribute_condition("os_version", "equals", &["17.4.0"])
    ));

    // A value that is not version shaped stays raw: semver rules fall through
    // conservatively and exact string operators still see the original form
    let mut raw = IdentityState::new_anonymous("anon-2".to_string());
    raw.identify(
        "user-43".to_string(),
        HashMap::from([(
            "os_version".to_string(),
            AttributeValue::String("17.4 beta".to_string()),
        )]),
        false,
    )
    .expect("identify succeeds");
    let raw_ctx = raw.context();
    assert!(!rule_matches(
        raw_ctx,
        attribute_condition("os_version", "sem_ver_gte", &["17.0.0"])
    ));
    assert!(rule_matches(
        raw_ctx,
        attribute_condition("os_version", "equals", &["17.4 beta"])
    ));
}

#[test]
fn real_device_version_shapes_target_correctly_end_to_end() {
    // The shapes each platform actually reports, walked through the same
    // normalize-then-evaluate chain the wrappers use. iOS formats os_version
    // from the version struct so it is always three components, Android
    // reports a bare major like "14", and an Android versionName commonly
    // carries a prerelease suffix, which is valid semver that passes through
    // canonicalization raw and still orders correctly
    let cases: &[(&str, &str, &str, &[&str], bool)] = &[
        // iOS struct-formatted os_version is already canonical
        ("os_version", "17.4.1", "sem_ver_gte", &["17.0.0"], true),
        // Android Build.VERSION.RELEASE bare major pads to three components
        ("os_version", "14", "sem_ver_gte", &["14.0.0"], true),
        ("os_version", "14", "sem_ver_lt", &["15.0.0"], true),
        // Android preview builds can report a codename, which is not version
        // shaped: semver rules fall through conservatively
        ("os_version", "Baklava", "sem_ver_gte", &["14.0.0"], false),
        // iOS CFBundleShortVersionString two-component convention pads
        ("app_version", "2.1", "sem_ver_eq", &["2.1.0"], true),
        // Android versionName with a prerelease suffix passes through raw and
        // orders below its release per semver precedence
        (
            "app_version",
            "2.1.0-beta.3",
            "sem_ver_lt",
            &["2.1.0"],
            true,
        ),
        (
            "app_version",
            "2.1.0-beta.3",
            "sem_ver_gte",
            &["2.1.0"],
            false,
        ),
        // The raw prerelease form still matches itself exactly
        (
            "app_version",
            "2.1.0-beta.3",
            "equals",
            &["2.1.0-beta.3"],
            true,
        ),
        // Build metadata is ignored for semver precedence
        ("app_version", "2.1.0+42", "sem_ver_eq", &["2.1.0"], true),
    ];
    for (attribute, reported, operator, values, expected) in cases {
        let mut identity = IdentityState::new_anonymous("anon".to_string());
        identity
            .identify(
                "user-1".to_string(),
                HashMap::from([(
                    attribute.to_string(),
                    AttributeValue::String(reported.to_string()),
                )]),
                false,
            )
            .expect("identify succeeds");
        let matched = rule_matches(
            identity.context(),
            attribute_condition(attribute, operator, values),
        );
        assert_eq!(
            matched, *expected,
            "{attribute}={reported} {operator} {values:?}"
        );
    }
}
