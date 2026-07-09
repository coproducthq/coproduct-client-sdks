use std::collections::HashMap;

use coproduct_core::context::AttributeValue;
use coproduct_core::identity_state::{AUTO_POPULATED_ATTRIBUTE_NAMES, IdentityState};

fn upsert(state: &mut IdentityState, entries: &[(&str, AttributeValue)]) {
    let map: HashMap<String, AttributeValue> = entries
        .iter()
        .map(|(k, v)| (k.to_string(), v.clone()))
        .collect();
    state.set_auto_populated_attributes(map);
}

#[test]
fn allowlist_covers_exactly_the_sdk_owned_names() {
    let expected = [
        "timezone",
        "platform",
        "os_version",
        "app_version",
        "app_build",
        "locale",
        "device_type",
        "network_type",
        "first_seen_at",
        "session_count",
    ];
    assert_eq!(AUTO_POPULATED_ATTRIBUTE_NAMES, &expected);
}

#[test]
fn accepted_names_land_in_the_auto_populated_layer() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    upsert(
        &mut state,
        &[
            ("platform", AttributeValue::String("ios".to_string())),
            ("session_count", AttributeValue::Number(3.0)),
        ],
    );
    assert_eq!(
        state.context().get_attribute("platform"),
        Some(AttributeValue::String("ios".to_string()))
    );
    assert_eq!(
        state.context().get_attribute("session_count"),
        Some(AttributeValue::Number(3.0))
    );
}

#[test]
fn identity_geo_and_custom_names_are_dropped() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    upsert(
        &mut state,
        &[
            ("user_id", AttributeValue::String("shadow".to_string())),
            ("targetingKey", AttributeValue::String("shadow".to_string())),
            ("country", AttributeValue::String("DE".to_string())),
            ("continent", AttributeValue::String("EU".to_string())),
            ("region_code", AttributeValue::String("BE".to_string())),
            ("city", AttributeValue::String("Berlin".to_string())),
            ("plan", AttributeValue::String("pro".to_string())),
        ],
    );
    // user_id still resolves to the targeting key, and none of the rejected
    // names produced an auto-populated entry
    assert_eq!(
        state.context().get_attribute("user_id"),
        Some(AttributeValue::String("anon".to_string()))
    );
    assert_eq!(state.context().get_attribute("country"), None);
    assert_eq!(state.context().get_attribute("continent"), None);
    assert_eq!(state.context().get_attribute("region_code"), None);
    assert_eq!(state.context().get_attribute("city"), None);
    assert_eq!(state.context().get_attribute("plan"), None);
}

#[test]
fn auto_populated_values_shadow_sdk_context() {
    // The device timezone must win over the edge's IP-derived fallback, which
    // is the layer-precedence half of the timezone conformance point
    let mut state = IdentityState::new_anonymous("anon".to_string());
    state
        .context_mut()
        .set_sdk_context("timezone", AttributeValue::String("UTC".to_string()));
    upsert(
        &mut state,
        &[(
            "timezone",
            AttributeValue::String("America/New_York".to_string()),
        )],
    );
    assert_eq!(
        state.context().get_attribute("timezone"),
        Some(AttributeValue::String("America/New_York".to_string()))
    );
}

#[test]
fn null_values_are_dropped_so_lower_layers_stay_reachable() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    state
        .context_mut()
        .set_sdk_context("timezone", AttributeValue::String("UTC".to_string()));
    upsert(&mut state, &[("timezone", AttributeValue::Null)]);
    // A stored Null would shadow the sdkContext fallback while reading as not
    // set. The upsert drops it instead, so the fallback stays reachable
    assert_eq!(
        state.context().get_attribute("timezone"),
        Some(AttributeValue::String("UTC".to_string()))
    );
}

#[test]
fn values_normalize_on_the_auto_path() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    upsert(
        &mut state,
        &[
            ("locale", AttributeValue::String("en_US".to_string())),
            ("os_version", AttributeValue::String("17.4".to_string())),
        ],
    );
    assert_eq!(
        state.context().get_attribute("locale"),
        Some(AttributeValue::String("en-US".to_string()))
    );
    assert_eq!(
        state.context().get_attribute("os_version"),
        Some(AttributeValue::String("17.4.0".to_string()))
    );
}

#[test]
fn upsert_merges_and_omitted_keys_survive() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    upsert(
        &mut state,
        &[
            ("platform", AttributeValue::String("ios".to_string())),
            ("network_type", AttributeValue::String("wifi".to_string())),
        ],
    );
    upsert(
        &mut state,
        &[(
            "network_type",
            AttributeValue::String("cellular".to_string()),
        )],
    );
    assert_eq!(
        state.context().get_attribute("network_type"),
        Some(AttributeValue::String("cellular".to_string()))
    );
    assert_eq!(
        state.context().get_attribute("platform"),
        Some(AttributeValue::String("ios".to_string()))
    );
}

#[test]
fn developer_attributes_win_and_sign_out_preserves_the_layer() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    upsert(
        &mut state,
        &[(
            "timezone",
            AttributeValue::String("America/New_York".to_string()),
        )],
    );
    state
        .identify(
            "user-1".to_string(),
            HashMap::from([(
                "timezone".to_string(),
                AttributeValue::String("Europe/Berlin".to_string()),
            )]),
            false,
        )
        .expect("identify succeeds");
    assert_eq!(
        state.context().get_attribute("timezone"),
        Some(AttributeValue::String("Europe/Berlin".to_string()))
    );
    state.sign_out();
    // The developer override cleared with identity, the auto value survives
    assert_eq!(
        state.context().get_attribute("timezone"),
        Some(AttributeValue::String("America/New_York".to_string()))
    );
}

#[test]
fn non_finite_numbers_are_dropped_so_the_no_op_gate_stays_silent() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    let entries: HashMap<String, AttributeValue> = HashMap::from([(
        "session_count".to_string(),
        AttributeValue::Number(f64::NAN),
    )]);
    assert!(!state.set_auto_populated_attributes(entries.clone()));
    assert_eq!(state.context().get_attribute("session_count"), None);
    // Repeating the same NaN upsert must stay a no-op rather than reporting
    // changed on every identical call, which is the failure this guards against
    assert!(!state.set_auto_populated_attributes(entries));
    assert_eq!(state.context().get_attribute("session_count"), None);
}

#[test]
fn the_upsert_reports_whether_the_layer_actually_changed() {
    let mut state = IdentityState::new_anonymous("anon".to_string());
    let wifi = [("network_type", AttributeValue::String("wifi".to_string()))];
    let map = |entries: &[(&str, AttributeValue)]| -> HashMap<String, AttributeValue> {
        entries
            .iter()
            .map(|(k, v)| (k.to_string(), v.clone()))
            .collect()
    };
    assert!(state.set_auto_populated_attributes(map(&wifi)));
    // The same normalized value again changes nothing
    assert!(!state.set_auto_populated_attributes(map(&wifi)));
    // Rejected names and null values change nothing either
    assert!(!state.set_auto_populated_attributes(map(&[
        ("plan", AttributeValue::String("pro".to_string())),
        ("timezone", AttributeValue::Null),
    ])));
    assert!(state.set_auto_populated_attributes(map(&[(
        "network_type",
        AttributeValue::String("cellular".to_string())
    )])));
}
