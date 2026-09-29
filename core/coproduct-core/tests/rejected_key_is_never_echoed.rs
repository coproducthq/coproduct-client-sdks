use async_trait::async_trait;
use coproduct_core::client::CoproductClient;
use coproduct_core::config::CoproductConfig;
use coproduct_core::error::InitError;
use coproduct_core::secure_store::{SecureStore, SecureStoreError};
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

const INVALID_KEY_TYPE_SENTENCE: &str =
    "invalid SDK key type: expected a Coproduct mobile SDK key (cpk_mob_)";

const REJECTED_KEYS: &[&str] = &[
    "cpk_web_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "svc_live_abcdefghijklmnopqrstuvwxyz",
    "password_hunter2",
    "abc123_def456_rest",
    "sk8Fj3kQ9xLmP2vR7tYw",
    "Bearer_eyJhbGciOiJIUzI1NiJ9",
    "_secret",
    "secret_",
    "token_\nforged-log-line",
    "token_\u{1b}[31mred",
];

const SECRET_FRAGMENTS: &[&str] = &["hunter2", "def456", "eyJhbGciOi", "forged-log-line"];

#[derive(Debug)]
struct NeverTransport;

#[async_trait]
impl Transport for NeverTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        std::future::pending::<()>().await;
        unreachable!()
    }
}

#[derive(Debug, Default)]
struct InMemorySecureStore {
    inner: Mutex<std::collections::HashMap<String, String>>,
}

#[async_trait]
impl SecureStore for InMemorySecureStore {
    async fn read(&self, key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(self.inner.lock().get(&key).cloned())
    }
    async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError> {
        self.inner.lock().insert(key, value);
        Ok(())
    }
}

fn initialize_error(sdk_key: &str) -> InitError {
    let dir = TempDir::new().unwrap();
    let result = futures::executor::block_on(CoproductClient::initialize(
        sdk_key.to_string(),
        "coproduct-ios/test".to_string(),
        CoproductConfig::default(),
        dir.path().to_string_lossy().into_owned(),
        Arc::new(NeverTransport),
        Arc::new(InMemorySecureStore::default()),
    ));
    match result {
        Ok(_) => panic!("key must be rejected at the validation gate"),
        Err(err) => err,
    }
}

/// A 40-character mobile key whose body is valid except for `bad` at `index`
fn mobile_key_with_bad_char(index: usize, bad: char) -> String {
    let mut body: Vec<char> = "a".repeat(32).chars().collect();
    body[index] = bad;
    format!("cpk_mob_{}", body.into_iter().collect::<String>())
}

fn assert_absent(rendered: &str, needle: &str, label: &str) {
    assert!(
        !rendered.contains(needle),
        "{label} must not contain {needle:?}, got {rendered:?}"
    );
}

#[test]
fn wrong_key_type_reports_a_fixed_sentence_and_a_redacted_prefix() {
    for &key in REJECTED_KEYS {
        let err = initialize_error(key);
        match &err {
            InitError::InvalidKeyType { prefix } => {
                assert_eq!(prefix, "(redacted)", "prefix for {key:?}");
            }
            other => panic!("expected InvalidKeyType for {key:?}, got {other:?}"),
        }
        assert_eq!(
            err.to_string(),
            INVALID_KEY_TYPE_SENTENCE,
            "Display for {key:?}"
        );

        let display = err.to_string();
        let debug = format!("{err:?}");
        let escaped_key = key.escape_debug().to_string();
        for rendered in [&display, &debug] {
            assert_absent(rendered, key, "rendered error");
            assert_absent(rendered, &escaped_key, "rendered error");
            for fragment in SECRET_FRAGMENTS {
                assert_absent(rendered, fragment, "rendered error");
            }
        }
    }
}

#[test]
fn malformed_character_reports_only_its_position() {
    // Exact equality is the guard for letters the fixed wording already contains, such as `i`
    // Multibyte characters are counted as one character each, so they reach this
    // check and report their position like any other invalid character
    let cases = [
        (0, 'A'),
        (5, 'i'),
        (17, '\n'),
        (31, '\u{1b}'),
        (31, '\u{e9}'),
        (10, '\u{20ac}'),
    ];
    for (index, bad) in cases {
        let key = mobile_key_with_bad_char(index, bad);
        assert_eq!(key.chars().count(), 40, "fixture must be correctly sized");
        let position = 8 + index;
        let expected_reason = format!(
            "invalid character at position {position}, expected lowercase Crockford base32"
        );

        let err = initialize_error(&key);
        match &err {
            InitError::MalformedSdkKey { reason } => {
                assert_eq!(reason, &expected_reason, "reason for {bad:?}");
            }
            other => panic!("expected MalformedSdkKey for {bad:?}, got {other:?}"),
        }
        assert_eq!(
            err.to_string(),
            format!("malformed SDK key: {expected_reason}")
        );

        let display = err.to_string();
        let debug = format!("{err:?}");
        for rendered in [&display, &debug] {
            assert_absent(rendered, &key, "rendered error");
            assert_absent(rendered, &key.escape_debug().to_string(), "rendered error");
            assert_absent(rendered, &format!("`{bad}`"), "rendered error");
            if bad.is_control() || !bad.is_ascii() {
                assert_absent(rendered, &bad.to_string(), "rendered error");
                assert_absent(rendered, &bad.escape_debug().to_string(), "rendered error");
            }
        }
    }
}

#[test]
fn wrong_length_reports_only_lengths() {
    let err = initialize_error("cpk_mob_abc123");
    match &err {
        InitError::MalformedSdkKey { reason } => {
            assert_eq!(reason, "expected 40 characters total, got 14");
        }
        other => panic!("expected MalformedSdkKey, got {other:?}"),
    }
    assert_absent(&format!("{err:?}"), "abc123", "Debug");
    assert_absent(&err.to_string(), "abc123", "Display");
}

#[test]
fn multibyte_key_length_is_counted_in_characters() {
    // 40 bytes but only 39 characters, because the final character takes two bytes
    let key = format!("cpk_mob_{}\u{e9}", "a".repeat(30));
    assert_eq!(key.len(), 40, "fixture must be 40 bytes");
    let err = initialize_error(&key);
    match &err {
        InitError::MalformedSdkKey { reason } => {
            assert_eq!(reason, "expected 40 characters total, got 39");
        }
        other => panic!("expected MalformedSdkKey, got {other:?}"),
    }
    for rendered in [err.to_string(), format!("{err:?}")] {
        assert_absent(&rendered, "\u{e9}", "rendered error");
        assert_absent(&rendered, &key, "rendered error");
    }
}
