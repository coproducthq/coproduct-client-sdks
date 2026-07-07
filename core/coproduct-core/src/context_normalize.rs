use crate::context::AttributeValue;

/// Apply the normalization contract for one attribute. Only `locale`, `country`,
/// `continent`, and `region_code` are transformed; every other name passes
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
