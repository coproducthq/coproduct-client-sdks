use coproduct_core::context::EvaluationContext;
use coproduct_core::pipeline::{RequestedType, evaluate};
use coproduct_core::snapshot::test_support::case_runner::{
    PipelineCase, expand_template, load_pipeline_cases,
};

fn requested_type_from_str(s: &str) -> RequestedType {
    match s {
        "bool" => RequestedType::Bool,
        "string" => RequestedType::String,
        "int" => RequestedType::Int,
        "number" => RequestedType::Number,
        "json" => RequestedType::Json,
        other => panic!("unknown requested_type: {other}"),
    }
}

#[test]
fn all_pipeline_cases_match_expected_output() {
    let cases: Vec<PipelineCase> = load_pipeline_cases("../../tests/cases.json");
    let ctx = EvaluationContext::with_targeting_key("conformance-user");

    for case in cases {
        let snapshot = expand_template(&case);
        let outcome = evaluate(
            snapshot.as_ref(),
            &case.flag_key,
            requested_type_from_str(&case.requested_type),
            &ctx,
        );

        if let Some(expected) = case.expected_error_code.as_deref() {
            let actual = outcome.error_code.map(|c| c.as_wire()).unwrap_or("<none>");
            assert_eq!(
                actual, expected,
                "case {:?}: error_code mismatch",
                case.name
            );
        }
        if let Some(expected) = case.expected_variation.as_deref() {
            assert_eq!(
                outcome.variation_key.as_deref(),
                Some(expected),
                "case {:?}: variation mismatch",
                case.name
            );
        }
        if let Some(expected) = case.expected_reason.as_deref() {
            let actual = format!("{:?}", outcome.reason).to_lowercase();
            let want = expected.replace('_', "");
            assert!(
                actual.replace('_', "").eq_ignore_ascii_case(&want),
                "case {:?}: reason mismatch, got {actual}",
                case.name
            );
        }
    }
}
