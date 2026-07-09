use crate::context::AttributeValue;

/// Apply the normalization contract for one attribute. Only `locale`,
/// `country`, `continent`, `region_code`, `os_version`, and `app_version` are
/// transformed; every other name passes through unchanged. This enforces
/// uniform string shape so every binding buckets on identical inputs
pub fn normalize_attribute(name: &str, value: AttributeValue) -> AttributeValue {
    match (name, value) {
        ("locale", AttributeValue::String(s)) => AttributeValue::String(s.replace('_', "-")),
        ("country", AttributeValue::String(s)) => AttributeValue::String(s.to_uppercase()),
        ("continent", AttributeValue::String(s)) => AttributeValue::String(s.to_uppercase()),
        ("region_code", AttributeValue::String(s)) => AttributeValue::String(s.to_uppercase()),
        ("os_version" | "app_version", AttributeValue::String(s)) => {
            match canonicalize_version(&s) {
                Some(canonical) => AttributeValue::String(canonical),
                None => AttributeValue::String(s),
            }
        }
        (_, value) => value,
    }
}

/// Canonicalize a version-shaped string to exactly three numeric components so
/// it compares against the canonical rule values the platform stores on write:
/// pad missing minor and patch with zeros, keep the first three parts of a
/// longer dotted string, and accept an optional leading `v`. Devices report
/// versions like `"17.4"` (iOS `systemVersion`) or `"14"` (Android release)
/// that a strict semver parse rejects, so without this every `sem_ver_*` rule
/// on `os_version` silently never matches. Returns `None` for anything not
/// version shaped, and the caller passes the raw value through so a rule can
/// still match it with exact string operators
fn canonicalize_version(value: &str) -> Option<String> {
    let digits = value.strip_prefix('v').unwrap_or(value);
    if digits.is_empty() {
        return None;
    }
    let mut components = [0u64; 3];
    for (index, part) in digits.split('.').enumerate() {
        if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        if index < 3 {
            components[index] = part.parse().ok()?;
        }
    }
    Some(format!(
        "{}.{}.{}",
        components[0], components[1], components[2]
    ))
}
