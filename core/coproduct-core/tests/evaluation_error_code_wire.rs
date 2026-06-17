use coproduct_core::error::EvaluationErrorCode;

#[test]
fn all_seven_variants_serialize_to_screaming_snake() {
    let cases = [
        (EvaluationErrorCode::FlagNotFound, "FLAG_NOT_FOUND"),
        (EvaluationErrorCode::TypeMismatch, "TYPE_MISMATCH"),
        (EvaluationErrorCode::ParseError, "PARSE_ERROR"),
        (EvaluationErrorCode::RuleCircuitBreak, "RULE_CIRCUIT_BREAK"),
        (EvaluationErrorCode::ProviderNotReady, "PROVIDER_NOT_READY"),
        (EvaluationErrorCode::ProviderFatal, "PROVIDER_FATAL"),
        (EvaluationErrorCode::General, "GENERAL"),
    ];
    for (variant, wire) in cases {
        assert_eq!(variant.as_wire(), wire);
        assert_eq!(format!("{variant}"), wire);
    }
}

#[test]
fn variants_round_trip_through_serde() {
    let value = EvaluationErrorCode::RuleCircuitBreak;
    let json = serde_json::to_string(&value).unwrap();
    assert_eq!(json, "\"RULE_CIRCUIT_BREAK\"");
    let back: EvaluationErrorCode = serde_json::from_str(&json).unwrap();
    assert_eq!(back, value);
}

#[test]
fn variants_implement_copy_and_eq() {
    let a = EvaluationErrorCode::TypeMismatch;
    let b = a;
    assert_eq!(a, b);
}
