use std::fmt;

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Errors that can fail `initialize(...)` synchronously. Per spec, these are
/// non-recoverable misconfigurations only. Network failures during start do
/// not surface here. The SDK enters notReady and continues in background
#[derive(Debug, Error)]
pub enum InitError {
    #[error("invalid SDK key type: expected cpk_mob_, got {prefix}")]
    InvalidKeyType { prefix: String },

    #[error("malformed SDK key: {reason}")]
    MalformedSdkKey { reason: String },

    #[error("missing SDK key: initialize requires a non-empty cpk_mob_ key")]
    MissingSdkKey,

    #[error("invalid config: field `{field}` {reason}")]
    InvalidConfig { field: String, reason: String },

    #[error("unsupported schema version: snapshot is {actual}, SDK supports {supported}")]
    UnsupportedSchemaVersion { actual: u32, supported: u32 },
}

/// Error codes returned in `FlagEvaluationDetails.errorCode` when an
/// evaluation cannot produce a real flag value. Aligns with OpenFeature so
/// consumers familiar with that spec see the codes they expect. Serialized as
/// uppercase strings (e.g. `FLAG_NOT_FOUND`) when crossing the FFI boundary
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum EvaluationErrorCode {
    #[serde(rename = "FLAG_NOT_FOUND")]
    FlagNotFound,
    #[serde(rename = "TYPE_MISMATCH")]
    TypeMismatch,
    #[serde(rename = "PARSE_ERROR")]
    ParseError,
    #[serde(rename = "RULE_CIRCUIT_BREAK")]
    RuleCircuitBreak,
    #[serde(rename = "PROVIDER_NOT_READY")]
    ProviderNotReady,
    #[serde(rename = "PROVIDER_FATAL")]
    ProviderFatal,
    #[serde(rename = "GENERAL")]
    General,
}

impl EvaluationErrorCode {
    /// Returns the uppercase string that appears in JSON snapshots (e.g. `FLAG_NOT_FOUND`)
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::FlagNotFound => "FLAG_NOT_FOUND",
            Self::TypeMismatch => "TYPE_MISMATCH",
            Self::ParseError => "PARSE_ERROR",
            Self::RuleCircuitBreak => "RULE_CIRCUIT_BREAK",
            Self::ProviderNotReady => "PROVIDER_NOT_READY",
            Self::ProviderFatal => "PROVIDER_FATAL",
            Self::General => "GENERAL",
        }
    }
}

impl fmt::Display for EvaluationErrorCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_wire())
    }
}

/// Configuration validation failures. Surfaced from `validate_config` and
/// converted to `InitError::InvalidConfig` at the initialize boundary
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ConfigError {
    #[error("invalid pollInterval: {actual:?} is less than minimum {minimum:?}")]
    PollIntervalTooSmall {
        actual: std::time::Duration,
        minimum: std::time::Duration,
    },

    #[error("invalid startupTimeout: must be greater than zero")]
    StartupTimeoutNonPositive,

    #[error("invalid endpoint: `{value}` is not a parseable URL")]
    InvalidEndpoint { value: String },
}

impl From<ConfigError> for InitError {
    fn from(err: ConfigError) -> Self {
        let (field, reason) = match &err {
            ConfigError::PollIntervalTooSmall { .. } => ("pollInterval", err.to_string()),
            ConfigError::StartupTimeoutNonPositive => ("startupTimeout", err.to_string()),
            ConfigError::InvalidEndpoint { .. } => ("endpoint", err.to_string()),
        };
        InitError::InvalidConfig {
            field: field.to_string(),
            reason,
        }
    }
}

/// Network request errors, mapped from the platform's native error type
/// (URLSession on iOS, OkHttp on Android, fetch elsewhere) into a small set
/// the SDK classifies uniformly: retry on recoverable variants, stop polling
/// and fail closed on `Unauthorized`
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum TransportError {
    #[error("transport timeout")]
    Timeout,

    #[error("network unreachable")]
    NetworkUnreachable,

    #[error("unauthorized: SDK key revoked, unknown, or wrong type")]
    Unauthorized,

    #[error("server error: status {status}")]
    ServerError { status: u16 },

    #[error("malformed response body")]
    MalformedResponse,

    #[error("transport error: {message}")]
    Other { message: String },
}

/// Secure-store failure modes. Per spec, secure-store failures are
/// log-and-continue: the SDK does not refuse to evaluate when the keychain is
/// locked or absent, it falls back to in-memory identity
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum SecureStoreError {
    #[error("secure store unavailable on this device")]
    Unavailable,

    #[error("secure store value corrupted")]
    Corrupted,

    #[error("secure store write failed")]
    WriteFailed,

    #[error("secure store read failed")]
    ReadFailed,
}
