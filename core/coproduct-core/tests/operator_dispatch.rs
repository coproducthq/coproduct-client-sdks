use coproduct_core::context::AttributeValue;
use coproduct_core::operators::{Operator, evaluate};
use coproduct_core::snapshot::ConditionOutcome;

// Rule values arrive as string arrays on the wire (the platform value schema is
// a list of strings). Numeric operators parse the strings; string operators use
// them directly
fn rhs(vals: &[&str]) -> Vec<String> {
    vals.iter().map(|s| s.to_string()).collect()
}

#[test]
fn equals_string_match() {
    let lhs = AttributeValue::String("premium".to_string());
    assert_eq!(
        evaluate(Operator::Equals, &lhs, &rhs(&["premium"])),
        ConditionOutcome::Match
    );
}

#[test]
fn equals_string_disagrees_returns_nomatch() {
    let lhs = AttributeValue::String("free".to_string());
    assert_eq!(
        evaluate(Operator::Equals, &lhs, &rhs(&["premium"])),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn equals_number_match_via_stringify() {
    let lhs = AttributeValue::Number(42.0);
    assert_eq!(
        evaluate(Operator::Equals, &lhs, &rhs(&["42"])),
        ConditionOutcome::Match
    );
}

#[test]
fn equals_bool_match_via_stringify() {
    let lhs = AttributeValue::Bool(true);
    assert_eq!(
        evaluate(Operator::Equals, &lhs, &rhs(&["true"])),
        ConditionOutcome::Match
    );
}

#[test]
fn equals_null_lhs_is_indeterminate() {
    let lhs = AttributeValue::Null;
    assert_eq!(
        evaluate(Operator::Equals, &lhs, &rhs(&["anything"])),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn not_equals_flips_genuine_disagreement_to_match() {
    let lhs = AttributeValue::String("free".to_string());
    assert_eq!(
        evaluate(Operator::NotEquals, &lhs, &rhs(&["premium"])),
        ConditionOutcome::Match
    );
}

#[test]
fn not_equals_on_null_lhs_stays_indeterminate() {
    let lhs = AttributeValue::Null;
    assert_eq!(
        evaluate(Operator::NotEquals, &lhs, &rhs(&["anything"])),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn gt_numeric() {
    let lhs = AttributeValue::Number(60.0);
    assert_eq!(
        evaluate(Operator::Gt, &lhs, &rhs(&["50"])),
        ConditionOutcome::Match
    );
}

#[test]
fn gt_decimal_rhs() {
    let lhs = AttributeValue::Number(3.5);
    assert_eq!(
        evaluate(Operator::Gt, &lhs, &rhs(&["3.14"])),
        ConditionOutcome::Match
    );
}

#[test]
fn gt_non_numeric_lhs_is_indeterminate() {
    let lhs = AttributeValue::String("high".to_string());
    assert_eq!(
        evaluate(Operator::Gt, &lhs, &rhs(&["50"])),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn numeric_op_rejects_scientific_hex_and_special_strings() {
    let lhs = AttributeValue::Number(100.0);
    for bad in ["1e3", "0x10", "NaN", "Infinity", ""] {
        assert_eq!(
            evaluate(Operator::Gt, &lhs, &rhs(&[bad])),
            ConditionOutcome::Indeterminate,
            "bad RHS string `{bad}` must produce Indeterminate"
        );
    }
}

#[test]
fn gt_with_only_disagreeing_rhs_is_nomatch() {
    let lhs = AttributeValue::Number(10.0);
    assert_eq!(
        evaluate(Operator::Gt, &lhs, &rhs(&["50", "100"])),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn gte_lt_lte_numeric() {
    let lhs = AttributeValue::Number(50.0);
    assert_eq!(
        evaluate(Operator::Gte, &lhs, &rhs(&["50"])),
        ConditionOutcome::Match
    );
    assert_eq!(
        evaluate(Operator::Lt, &lhs, &rhs(&["50"])),
        ConditionOutcome::NoMatch
    );
    assert_eq!(
        evaluate(Operator::Lte, &lhs, &rhs(&["50"])),
        ConditionOutcome::Match
    );
}

#[test]
fn in_string_member() {
    let lhs = AttributeValue::String("us".to_string());
    assert_eq!(
        evaluate(Operator::In, &lhs, &rhs(&["us", "ca", "uk"])),
        ConditionOutcome::Match
    );
}

#[test]
fn not_in_string_non_member() {
    let lhs = AttributeValue::String("fr".to_string());
    assert_eq!(
        evaluate(Operator::NotIn, &lhs, &rhs(&["us", "ca", "uk"])),
        ConditionOutcome::Match
    );
}

#[test]
fn starts_with_ends_with_contains() {
    let lhs = AttributeValue::String("alice@example.com".to_string());
    assert_eq!(
        evaluate(Operator::StartsWith, &lhs, &rhs(&["alice"])),
        ConditionOutcome::Match
    );
    assert_eq!(
        evaluate(Operator::EndsWith, &lhs, &rhs(&["@example.com"])),
        ConditionOutcome::Match
    );
    assert_eq!(
        evaluate(Operator::Contains, &lhs, &rhs(&["@example"])),
        ConditionOutcome::Match
    );
    assert_eq!(
        evaluate(Operator::NotContains, &lhs, &rhs(&["@example"])),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn string_op_on_non_string_lhs_is_indeterminate() {
    let lhs = AttributeValue::Number(42.0);
    assert_eq!(
        evaluate(Operator::StartsWith, &lhs, &rhs(&["4"])),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn equals_with_empty_values_is_indeterminate() {
    let lhs = AttributeValue::String("premium".to_string());
    let r: Vec<String> = vec![];
    assert_eq!(
        evaluate(Operator::Equals, &lhs, &r),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn compare_number_mixed_rhs_no_agreement_is_indeterminate() {
    // A parseable-but-disagreeing value alongside an unparseable one means the
    // full RHS could not be checked, so the outcome stays Indeterminate rather
    // than NoMatch
    let lhs = AttributeValue::Number(10.0);
    assert_eq!(
        evaluate(Operator::Gt, &lhs, &rhs(&["50", "abc"])),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn compare_number_mixed_rhs_with_agreement_is_match() {
    // An agreeing value short-circuits to Match even when a later RHS element is
    // unparseable, because one satisfied comparison is enough to include the user
    let lhs = AttributeValue::Number(10.0);
    assert_eq!(
        evaluate(Operator::Gt, &lhs, &rhs(&["5", "abc"])),
        ConditionOutcome::Match
    );
}

#[test]
fn unknown_operator_circuit_breaks() {
    // The fail-closed sentinel: an operator the SDK does not recognize must not
    // pretend to evaluate
    let lhs = AttributeValue::String("anything".to_string());
    let r: Vec<String> = vec![];
    assert_eq!(
        evaluate(Operator::Unknown, &lhs, &r),
        ConditionOutcome::CircuitBreak
    );
}
