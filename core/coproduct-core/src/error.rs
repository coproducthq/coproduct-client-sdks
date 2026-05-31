use thiserror::Error;

#[derive(Debug, Error)]
pub enum InitError {
    #[error("invalid SDK key type: expected cpk_mob_, got {prefix}")]
    InvalidKeyType { prefix: String },
    #[error("unsupported schema version: snapshot is {actual}, SDK supports {supported}")]
    UnsupportedSchemaVersion { actual: u32, supported: u32 },
    #[error("transport failure: {message}")]
    Transport { message: String },
    #[error("secure-store failure: {message}")]
    SecureStore { message: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvaluationErrorCode {
    FlagNotFound,
    TypeMismatch,
    ParseError,
    RuleCircuitBreak,
    ProviderNotReady,
    ProviderFatal,
    General,
}
