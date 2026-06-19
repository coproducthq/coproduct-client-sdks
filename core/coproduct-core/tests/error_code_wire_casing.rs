use coproduct_core::error::EvaluationErrorCode;

#[test]
fn wire_codes_match_the_error_code_table() {
    let pairs: [(EvaluationErrorCode, &str); 7] = [
        (EvaluationErrorCode::FlagNotFound, "FLAG_NOT_FOUND"),
        (EvaluationErrorCode::TypeMismatch, "TYPE_MISMATCH"),
        (EvaluationErrorCode::ParseError, "PARSE_ERROR"),
        (EvaluationErrorCode::RuleCircuitBreak, "RULE_CIRCUIT_BREAK"),
        (EvaluationErrorCode::ProviderNotReady, "PROVIDER_NOT_READY"),
        (EvaluationErrorCode::ProviderFatal, "PROVIDER_FATAL"),
        (EvaluationErrorCode::General, "GENERAL"),
    ];
    for (code, expected) in pairs {
        assert_eq!(code.as_wire(), expected, "casing drift on {code:?}");
    }
}

#[test]
fn wire_codes_are_all_uppercase_snake() {
    let codes = [
        EvaluationErrorCode::FlagNotFound,
        EvaluationErrorCode::TypeMismatch,
        EvaluationErrorCode::ParseError,
        EvaluationErrorCode::RuleCircuitBreak,
        EvaluationErrorCode::ProviderNotReady,
        EvaluationErrorCode::ProviderFatal,
        EvaluationErrorCode::General,
    ];
    for code in codes {
        let wire = code.as_wire();
        assert!(
            wire.chars().all(|c| c.is_ascii_uppercase() || c == '_'),
            "{wire} contains a non-uppercase-or-underscore char"
        );
        assert!(!wire.starts_with('_'), "{wire} starts with underscore");
        assert!(!wire.ends_with('_'), "{wire} ends with underscore");
        assert!(!wire.contains("__"), "{wire} has a double underscore");
    }
}
