use coproduct_core::client::CoproductClient;
use coproduct_core::details::Reason;
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};
use coproduct_core::snapshot::{Flag, FlagType, Variation, VariationValue};

// The plain getter, the detail getter's value, and the observer must agree. On a
// circuit break they agree on the off variation's value, not the caller default,
// while the details still report reason ERROR and code RULE_CIRCUIT_BREAK.

// A bool flag with a null fallthrough and no matching rule trips RULE_CIRCUIT_BREAK
// and resolves to its off variation. The off variation carries `true` while the
// caller default below is `false`, so serving the default instead of the off value
// is visible
fn circuit_break_flag(key: &str) -> Flag {
    Flag {
        key: key.to_string(),
        r#type: FlagType::Bool,
        enabled: true,
        is_paused: false,
        variations: vec![
            Variation {
                key: "on".to_string(),
                value: VariationValue::Bool(false),
                name: None,
            },
            Variation {
                key: "off".to_string(),
                value: VariationValue::Bool(true),
                name: None,
            },
        ],
        off_variation: Some("off".to_string()),
        fallthrough_variation: None,
        targeting_rules: Vec::new(),
        prerequisites: Vec::new(),
        experiment: None,
    }
}

#[tokio::test]
async fn circuit_break_serves_the_off_value_on_both_getters() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![
        circuit_break_flag("cb"),
    ]))
    .await;

    let plain = client.get_bool("cb".to_string(), false);
    let details = client.get_bool_details("cb".to_string(), false);

    assert!(
        plain,
        "the plain getter serves the off value on a circuit break"
    );
    assert_eq!(
        details.value, plain,
        "the detail getter serves the same value as the plain getter"
    );
    // The details still surface the error alongside the served off variation
    assert_eq!(details.reason, Reason::Error);
    assert_eq!(details.error_code.as_deref(), Some("RULE_CIRCUIT_BREAK"));
    assert_eq!(details.variant.as_deref(), Some("off"));
}

#[tokio::test]
async fn missing_flag_serves_the_default_on_both_getters() {
    let client = CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![])).await;

    let plain = client.get_bool("nope".to_string(), true);
    let details = client.get_bool_details("nope".to_string(), true);

    assert!(
        plain,
        "no variation resolves, so the caller default is served"
    );
    assert_eq!(details.value, plain);
    assert_eq!(details.error_code.as_deref(), Some("FLAG_NOT_FOUND"));
    assert_eq!(details.variant, None);
}

#[tokio::test]
async fn type_mismatch_serves_the_default_on_both_getters() {
    // A bool flag requested as a string type-mismatches before any variation
    // resolves, so both getters serve the default
    let client =
        CoproductClient::test_instance_with_snapshot(snapshot_with_flags(vec![bool_flag(
            "b", true,
        )]))
        .await;

    let plain = client.get_string("b".to_string(), "fallback".to_string());
    let details = client.get_string_details("b".to_string(), "fallback".to_string());

    assert_eq!(plain, "fallback");
    assert_eq!(details.value, plain);
    assert_eq!(details.error_code.as_deref(), Some("TYPE_MISMATCH"));
    assert_eq!(details.variant, None);
}
