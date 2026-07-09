use coproduct_core::context::AttributeValue;
use coproduct_core::context_normalize::normalize_attribute;

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

#[test]
fn version_attributes_canonicalize_to_three_components() {
    for (input, expected) in [
        ("17.4", "17.4.0"),
        ("17", "17.0.0"),
        ("1.2.3", "1.2.3"),
        ("1.2.3.4", "1.2.3"),
        ("v1.2", "1.2.0"),
        ("17.04", "17.4.0"),
    ] {
        for name in ["os_version", "app_version"] {
            assert_eq!(
                normalize_attribute(name, AttributeValue::String(input.to_string())),
                AttributeValue::String(expected.to_string()),
                "{name} {input}"
            );
        }
    }
}

#[test]
fn non_version_shaped_values_pass_through_raw() {
    for input in ["17.4 beta", "banana", "", "1..2", "v", "1.2.3-rc.1"] {
        assert_eq!(
            normalize_attribute("os_version", AttributeValue::String(input.to_string())),
            AttributeValue::String(input.to_string()),
            "{input}"
        );
    }
}

#[test]
fn version_canonicalization_applies_only_to_the_version_attributes() {
    // app_build stays an opaque string and custom attributes keep raw semantics
    for name in ["app_build", "firmware_version"] {
        assert_eq!(
            normalize_attribute(name, AttributeValue::String("17.4".to_string())),
            AttributeValue::String("17.4".to_string()),
            "{name}"
        );
    }
}
