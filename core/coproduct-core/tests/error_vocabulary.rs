use coproduct_core::error::{EvaluationErrorCode, InitError};

#[test]
fn init_error_variants_exist() {
    let invalid_key = InitError::InvalidKeyType { prefix: "cpk_srv".into() };
    assert_eq!(format!("{}", invalid_key), "invalid SDK key type: expected cpk_mob_, got cpk_srv");

    let mismatch = InitError::UnsupportedSchemaVersion { actual: 2, supported: 1 };
    assert_eq!(format!("{}", mismatch), "unsupported schema version: snapshot is 2, SDK supports 1");

    let transport = InitError::Transport { message: "network down".into() };
    assert_eq!(format!("{}", transport), "transport failure: network down");

    let secure = InitError::SecureStore { message: "keychain locked".into() };
    assert_eq!(format!("{}", secure), "secure-store failure: keychain locked");
}

#[test]
fn evaluation_error_code_variants_exist() {
    let codes = [
        EvaluationErrorCode::FlagNotFound,
        EvaluationErrorCode::TypeMismatch,
        EvaluationErrorCode::ParseError,
        EvaluationErrorCode::RuleCircuitBreak,
        EvaluationErrorCode::ProviderNotReady,
        EvaluationErrorCode::ProviderFatal,
        EvaluationErrorCode::General,
    ];
    assert_eq!(codes.len(), 7);
}
