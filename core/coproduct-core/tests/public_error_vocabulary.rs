use coproduct_core::error::{EvaluationErrorCode, InitError};

#[test]
fn init_error_variants_exist() {
    let invalid_key = InitError::InvalidKeyType {
        prefix: "(redacted)".into(),
    };
    assert_eq!(
        format!("{}", invalid_key),
        "invalid SDK key type: expected a Coproduct mobile SDK key (cpk_mob_)"
    );

    let mismatch = InitError::UnsupportedSchemaVersion {
        actual: 2,
        supported: 1,
    };
    assert_eq!(
        format!("{}", mismatch),
        "unsupported schema version: snapshot is 2, SDK supports 1"
    );
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
