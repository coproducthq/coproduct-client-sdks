use crate::error::ConfigError;
use std::time::Duration;

/// Config the core accepts at `initialize`, holding only values the core reads,
/// validates, or persists. Host capabilities (transport, secure store) cross
/// through the dedicated `initialize` parameters, and the evaluation listener
/// through its own setter, so they are not fields here. Host-behavior settings
/// such as foreground refresh live on the host-facing configs rather than this
/// one. `poll_interval`, `startup_timeout`, and `endpoint` are checked by
/// `validate_config`; `anonymous_id` seeds cold-start identity
#[derive(Clone)]
pub struct CoproductConfig {
    pub poll_interval: Option<Duration>,
    pub startup_timeout: Option<Duration>,
    pub anonymous_id: Option<String>,
    pub endpoint: Option<String>,
}

// Note: `#[derive(Default)]` is not used because some fields have non-None
// defaults (poll_interval = 60s, startup_timeout = 3s)
impl Default for CoproductConfig {
    fn default() -> Self {
        Self {
            poll_interval: Some(Duration::from_secs(60)),
            startup_timeout: Some(Duration::from_secs(3)),
            anonymous_id: None,
            endpoint: None,
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
