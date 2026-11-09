use std::collections::HashMap;

/// The five UTM parameter keys recognized for acquisition attribution. Any
/// other query parameter is ignored
const UTM_KEYS: [&str; 5] = [
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "utm_content",
];

/**
 * Extracts the recognized UTM parameters from a URL or a bare query string.
 *
 * Accepts either a full URL ("https://host/path?utm_source=..#frag") or the
 * raw query portion alone ("utm_source=..&utm_medium=.."), because the Android
 * Play Install Referrer hands back the query with no scheme. The fragment is
 * ignored. Values are percent-decoded and "+" is decoded to a space, matching
 * form-encoded query conventions. Keys outside the recognized set are dropped,
 * and a key with an empty decoded value is omitted so presence checks stay
 * meaningful. When a key repeats, the last occurrence wins
 */
pub fn parse_utm_parameters(input: &str) -> HashMap<String, String> {
    let query = input.split_once('?').map_or(input, |(_, query)| query);
    let query = query.split('#').next().unwrap_or("");

    form_urlencoded::parse(query.as_bytes())
        .filter_map(|(key, value)| {
            let (key, value) = (key.trim(), value.trim());
            (UTM_KEYS.contains(&key) && !value.is_empty())
                .then(|| (key.to_string(), value.to_string()))
        })
        .collect()
}
