use coproduct_core::context::AttributeValue;
use coproduct_core::context_normalize::{RECOGNIZED_ATTRIBUTES, normalize_attribute};

#[test]
fn recognized_list_holds_every_standard_attribute() {
    assert_eq!(RECOGNIZED_ATTRIBUTES.len(), 16);
    for name in [
        "user_id",
        "email",
        "country",
        "continent",
        "region_code",
        "city",
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
    ] {
        assert!(
            RECOGNIZED_ATTRIBUTES.contains(&name),
            "missing recognized attribute {name}"
        );
    }
}

#[test]
fn locale_underscore_becomes_hyphen() {
    assert_eq!(
        normalize_attribute("locale", AttributeValue::String("en_US".to_string())),
        AttributeValue::String("en-US".to_string())
    );
}

#[test]
fn locale_already_hyphenated_is_unchanged() {
    assert_eq!(
        normalize_attribute("locale", AttributeValue::String("en-GB".to_string())),
        AttributeValue::String("en-GB".to_string())
    );
}

#[test]
fn country_is_uppercased() {
    assert_eq!(
        normalize_attribute("country", AttributeValue::String("us".to_string())),
        AttributeValue::String("US".to_string())
    );
}

#[test]
fn continent_is_uppercased() {
    assert_eq!(
        normalize_attribute("continent", AttributeValue::String("na".to_string())),
        AttributeValue::String("NA".to_string())
    );
}

#[test]
fn region_code_is_uppercased() {
    assert_eq!(
        normalize_attribute("region_code", AttributeValue::String("us-ca".to_string())),
        AttributeValue::String("US-CA".to_string())
    );
}

#[test]
fn platform_passes_through_unchanged() {
    assert_eq!(
        normalize_attribute("platform", AttributeValue::String("ios".to_string())),
        AttributeValue::String("ios".to_string())
    );
    assert_eq!(
        normalize_attribute("platform", AttributeValue::String("toaster".to_string())),
        AttributeValue::String("toaster".to_string())
    );
}

#[test]
fn non_recognized_name_passes_through_unchanged() {
    assert_eq!(
        normalize_attribute(
            "plan_tier",
            AttributeValue::String("Enterprise".to_string())
        ),
        AttributeValue::String("Enterprise".to_string())
    );
}

#[test]
fn session_count_number_passes_through_unchanged() {
    assert_eq!(
        normalize_attribute("session_count", AttributeValue::Number(7.0)),
        AttributeValue::Number(7.0)
    );
}
