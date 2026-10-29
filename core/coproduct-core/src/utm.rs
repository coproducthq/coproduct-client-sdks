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
    let after_question = match input.find('?') {
        Some(i) => &input[i + 1..],
        None => input,
    };
    let query = after_question.split('#').next().unwrap_or("");

    let mut out = HashMap::new();
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (raw_key, raw_value) = match pair.split_once('=') {
            Some((k, v)) => (k, v),
            None => continue,
        };
        let key = percent_decode(raw_key);
        let key = key.trim();
        if !UTM_KEYS.contains(&key) {
            continue;
        }
        let value = percent_decode(raw_value);
        let value = value.trim();
        if value.is_empty() {
            continue;
        }
        out.insert(key.to_string(), value.to_string());
    }
    out
}

/// Decodes `%XX` escapes and "+" to space, lossily for any non-UTF-8 result.
/// A "%" not followed by two hex digits is passed through literally, so a
/// malformed referrer never panics
fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => {
                decoded.push(b' ');
                i += 1;
            }
            b'%' if i + 2 < bytes.len() => {
                let hi = (bytes[i + 1] as char).to_digit(16);
                let lo = (bytes[i + 2] as char).to_digit(16);
                match (hi, lo) {
                    (Some(h), Some(l)) => {
                        decoded.push((h * 16 + l) as u8);
                        i += 3;
                    }
                    _ => {
                        decoded.push(b'%');
                        i += 1;
                    }
                }
            }
            b => {
                decoded.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&decoded).into_owned()
}
