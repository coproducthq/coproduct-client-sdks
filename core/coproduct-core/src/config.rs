use crate::error::ConfigError;
use crate::logger::Logger;
use std::sync::Arc;
use std::time::Duration;

/// All v1.0 config fields. Field validation lands with the config validator
#[derive(Clone)]
pub struct CoproductConfig {
    pub poll_interval: Option<Duration>,
    pub startup_timeout: Option<Duration>,
    pub anonymous_id: Option<String>,
    pub logger: Option<Arc<dyn Logger>>,
    /// Platform-provided network transport (URLSession on iOS, OkHttp on Android, etc.)
    pub transport: Option<Arc<dyn std::any::Any + Send + Sync>>,
    /// Platform-provided secure storage (Keychain on iOS, EncryptedSharedPreferences on Android)
    pub secure_store: Option<Arc<dyn std::any::Any + Send + Sync>>,
    pub endpoint: Option<String>,
    pub poll_on_foreground: Option<bool>,
    /// Optional caller-supplied callback that observes every flag evaluation
    pub evaluation_listener: Option<Arc<dyn std::any::Any + Send + Sync>>,
    /// Per-request timeout. `None` delegates to the platform transport's own default
    pub request_timeout: Option<Duration>,
}

// Note: `#[derive(Default)]` is not used because some fields have non-None
// defaults (poll_interval = 60s, startup_timeout = 3s, poll_on_foreground = true)
impl Default for CoproductConfig {
    fn default() -> Self {
        Self {
            poll_interval: Some(Duration::from_secs(60)),
            startup_timeout: Some(Duration::from_secs(3)),
            anonymous_id: None,
            logger: None,
            transport: None,
            secure_store: None,
            endpoint: None,
            poll_on_foreground: Some(true),
            evaluation_listener: None,
            request_timeout: None,
        }
    }
}

/// Minimum allowed poll interval. Shorter intervals would wake the device more
/// often than the cached snapshot can meaningfully change
pub const MIN_POLL_INTERVAL: Duration = Duration::from_secs(30);

/// Validate config fields. Each field is optional, so only present values are
/// checked. Returns the first violation found so the caller can fail fast
pub fn validate_config(config: &CoproductConfig) -> Result<(), ConfigError> {
    if let Some(interval) = config.poll_interval
        && interval < MIN_POLL_INTERVAL
    {
        return Err(ConfigError::PollIntervalTooSmall {
            actual: interval,
            minimum: MIN_POLL_INTERVAL,
        });
    }

    if let Some(timeout) = config.startup_timeout
        && timeout.is_zero()
    {
        return Err(ConfigError::StartupTimeoutNonPositive);
    }

    if let Some(endpoint) = config.endpoint.as_deref()
        && !is_parseable_url(endpoint)
    {
        return Err(ConfigError::InvalidEndpoint {
            value: endpoint.to_string(),
        });
    }

    Ok(())
}

/// Parse endpoint URLs with the same syntax rules the transport layer will use
fn is_parseable_url(value: &str) -> bool {
    let Ok(uri) = value.parse::<http::Uri>() else {
        return false;
    };
    matches!(uri.scheme_str(), Some("http" | "https")) && uri.authority().is_some()
}
