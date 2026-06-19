use coproduct_core::context::AttributeValue;
use coproduct_core::operators::{Operator, evaluate};
use coproduct_core::snapshot::ConditionOutcome;

fn s(v: &str) -> AttributeValue {
    AttributeValue::String(v.to_string())
}

fn rhs(vals: &[&str]) -> Vec<String> {
    vals.iter().map(|s| s.to_string()).collect()
}

#[test]
fn sem_ver_eq_matches_canonical() {
    assert_eq!(
        evaluate(Operator::SemVerEq, &s("1.2.3"), &rhs(&["1.2.3"])),
        ConditionOutcome::Match
    );
}

#[test]
fn sem_ver_eq_ignores_build_metadata() {
    // Build metadata is ignored for precedence comparison per the semver
    // standard. Rust's `semver::Version` PartialEq includes build metadata, so
    // comparisons must go through ordering instead to stay consistent across
    // evaluators. `1.2.3+45` and `1.2.3` are equal
    assert_eq!(
        evaluate(Operator::SemVerEq, &s("1.2.3+45"), &rhs(&["1.2.3"])),
        ConditionOutcome::Match
    );
    assert_eq!(
        evaluate(Operator::SemVerEq, &s("1.2.3"), &rhs(&["1.2.3+45"])),
        ConditionOutcome::Match
    );
}

#[test]
fn sem_ver_gt_greater() {
    assert_eq!(
        evaluate(Operator::SemVerGt, &s("2.0.0"), &rhs(&["1.9.9"])),
        ConditionOutcome::Match
    );
}

#[test]
fn sem_ver_gt_equal_is_nomatch() {
    assert_eq!(
        evaluate(Operator::SemVerGt, &s("1.2.3"), &rhs(&["1.2.3"])),
        ConditionOutcome::NoMatch
    );
}

#[test]
fn sem_ver_gte_equal_is_match() {
    assert_eq!(
        evaluate(Operator::SemVerGte, &s("1.2.3"), &rhs(&["1.2.3"])),
        ConditionOutcome::Match
    );
}

#[test]
fn sem_ver_lt_less() {
    assert_eq!(
        evaluate(Operator::SemVerLt, &s("1.0.0"), &rhs(&["2.0.0"])),
        ConditionOutcome::Match
    );
}

#[test]
fn sem_ver_lte_equal_is_match() {
    assert_eq!(
        evaluate(Operator::SemVerLte, &s("1.2.3"), &rhs(&["1.2.3"])),
        ConditionOutcome::Match
    );
}

#[test]
fn sem_ver_prerelease_ordering() {
    // 1.2.3 is greater than 1.2.3-rc.1 per semver precedence
    assert_eq!(
        evaluate(Operator::SemVerGt, &s("1.2.3"), &rhs(&["1.2.3-rc.1"])),
        ConditionOutcome::Match
    );
}

#[test]
fn sem_ver_unparseable_lhs_is_indeterminate() {
    // Customer-supplied context might be malformed. The comparison cannot run,
    // so Indeterminate rather than NoMatch keeps a negated semver check over a
    // bad LHS from accidentally including the user
    assert_eq!(
        evaluate(Operator::SemVerGt, &s("not-a-version"), &rhs(&["1.0.0"])),
        ConditionOutcome::Indeterminate
    );
    assert_eq!(
        evaluate(Operator::SemVerEq, &s("v1"), &rhs(&["1.0.0"])),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn sem_ver_unparseable_rhs_is_indeterminate() {
    // Defense in depth: even though the server canonicalizes on write, a
    // corrupted snapshot must not crash. Indeterminate rather than NoMatch,
    // because RULE_CIRCUIT_BREAK is reserved for unknown operators or unknown
    // node types at the condition-tree layer
    assert_eq!(
        evaluate(Operator::SemVerGt, &s("1.0.0"), &rhs(&["totally garbage"])),
        ConditionOutcome::Indeterminate
    );
}

#[test]
fn sem_ver_non_string_lhs_is_indeterminate() {
    let lhs = AttributeValue::Number(1.0);
    assert_eq!(
        evaluate(Operator::SemVerEq, &lhs, &rhs(&["1.0.0"])),
        ConditionOutcome::Indeterminate
    );
}
