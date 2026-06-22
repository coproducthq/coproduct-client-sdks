use crate::context::AttributeValue;

/// The standard attributes the targeting engine recognizes for normalization
pub const RECOGNIZED_ATTRIBUTES: &[&str] = &[
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
];

/// Apply the normalization contract for one attribute. Non-recognized names pass
/// through unchanged. This enforces uniform string shape so every binding buckets
/// on identical inputs
pub fn normalize_attribute(name: &str, value: AttributeValue) -> AttributeValue {
    match (name, value) {
        ("locale", AttributeValue::String(s)) => AttributeValue::String(s.replace('_', "-")),
        ("country", AttributeValue::String(s)) => AttributeValue::String(s.to_uppercase()),
        ("continent", AttributeValue::String(s)) => AttributeValue::String(s.to_uppercase()),
        ("region_code", AttributeValue::String(s)) => AttributeValue::String(s.to_uppercase()),
        (_, value) => value,
    }
}
