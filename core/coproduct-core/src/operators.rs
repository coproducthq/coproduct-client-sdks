//! Attribute operator evaluation.
//!
//! The operator set itself is defined with the snapshot wire-format types in
//! `snapshot::rule` and re-exported here so evaluation callers have a single
//! import home. This module adds the evaluation semantics over that enum.
//!
//! The canonical operator set is owned by the platform schema, not by the SDK.
//! The SDK enum must match it exactly, which the parity test in
//! `tests/operator_surface_parity.rs` locks in. Adding, removing, or renaming an
//! operator requires a coordinated change on both sides and a schema-version
//! bump when the change is breaking, with whole-flag fail-closed as the safe
//! baseline

pub use crate::snapshot::Operator;

use crate::context::AttributeValue;
use crate::snapshot::ConditionOutcome;

/// Evaluates an operator against a context attribute and the rule value list,
/// returning a tetra-state outcome:
///
/// - `Match` means the values were comparable and agreed
/// - `NoMatch` means the values were comparable and disagreed
/// - `Indeterminate` means the comparison could not run (LHS type incompatible,
///   RHS empty, RHS unparseable, or LHS null). The condition tree's `Not`
///   combinator preserves this rather than flipping it to `Match`, which is what
///   makes a negated missing attribute safe
/// - `CircuitBreak` is reserved for an unknown operator reaching this path. The
///   condition tree normally short-circuits before calling here
///
/// Negated operators (`NotEquals`, `NotIn`, `NotContains`) are the negation of
/// their positive form so conservative negation applies uniformly: a
/// missing-LHS `NotEquals` returns `Indeterminate`, not an accidental `Match`
///
/// # Examples
///
/// ```
/// use coproduct_core::context::AttributeValue;
/// use coproduct_core::operators::{evaluate, Operator};
/// use coproduct_core::snapshot::ConditionOutcome;
///
/// let lhs = AttributeValue::String("alice@example.com".to_string());
/// let rhs = vec!["@example.com".to_string()];
/// assert_eq!(
///     evaluate(Operator::EndsWith, &lhs, &rhs),
///     ConditionOutcome::Match,
/// );
/// ```
pub fn evaluate(op: Operator, lhs: &AttributeValue, rhs: &[String]) -> ConditionOutcome {
    match op {
        Operator::Equals => string_equality(lhs, rhs),
        Operator::NotEquals => negate_outcome(string_equality(lhs, rhs)),
        Operator::In => string_equality(lhs, rhs),
        Operator::NotIn => negate_outcome(string_equality(lhs, rhs)),
        Operator::Gt => compare_number(lhs, rhs, |a, b| a > b),
        Operator::Gte => compare_number(lhs, rhs, |a, b| a >= b),
        Operator::Lt => compare_number(lhs, rhs, |a, b| a < b),
        Operator::Lte => compare_number(lhs, rhs, |a, b| a <= b),
        Operator::StartsWith => string_predicate(lhs, rhs, |hay, n| hay.starts_with(n)),
        Operator::EndsWith => string_predicate(lhs, rhs, |hay, n| hay.ends_with(n)),
        Operator::Contains => string_predicate(lhs, rhs, |hay, n| hay.contains(n)),
        Operator::NotContains => {
            negate_outcome(string_predicate(lhs, rhs, |hay, n| hay.contains(n)))
        }
        Operator::SemVerEq
        | Operator::SemVerGt
        | Operator::SemVerGte
        | Operator::SemVerLt
        | Operator::SemVerLte => evaluate_semver(op, lhs, rhs),
        // is_set / is_not_set never reach this dispatcher. The condition tree
        // routes them to their own helpers because they must observe `None` for
        // a missing attribute, and this function only sees the resolved
        // `&AttributeValue` form
        Operator::IsSet | Operator::IsNotSet => ConditionOutcome::Indeterminate,
        Operator::Unknown => ConditionOutcome::CircuitBreak,
    }
}

/// Negation table shared by the negated operator arms. Kept in this module so
/// the operators layer does not depend on the condition-tree layer (the
/// dependency runs one way: the condition tree imports operators, not the
/// reverse)
fn negate_outcome(outcome: ConditionOutcome) -> ConditionOutcome {
    match outcome {
        ConditionOutcome::Match => ConditionOutcome::NoMatch,
        ConditionOutcome::NoMatch => ConditionOutcome::Match,
        ConditionOutcome::Indeterminate => ConditionOutcome::Indeterminate,
        ConditionOutcome::CircuitBreak => ConditionOutcome::CircuitBreak,
    }
}

/// Project an `AttributeValue` to its string form for the string-family
/// operators. `Number` uses Rust's default `Display`, which matches the
/// platform's default string conversion for finite values. `Null`, `Array`, and
/// `Object` return `None` so a comparison against a literal cannot accidentally
/// succeed
fn lhs_as_string(lhs: &AttributeValue) -> Option<String> {
    match lhs {
        AttributeValue::String(s) => Some(s.clone()),
        AttributeValue::Number(n) => Some(n.to_string()),
        AttributeValue::Bool(b) => Some(b.to_string()),
        AttributeValue::Null | AttributeValue::Array(_) | AttributeValue::Object(_) => None,
    }
}

/// Equality and set-membership share the same shape: stringify the LHS, then
/// scan the RHS for an exact match. A non-stringifiable LHS or an empty RHS
/// yields `Indeterminate` because the comparison cannot proceed
fn string_equality(lhs: &AttributeValue, rhs: &[String]) -> ConditionOutcome {
    let Some(lhs_str) = lhs_as_string(lhs) else {
        return ConditionOutcome::Indeterminate;
    };
    if rhs.is_empty() {
        return ConditionOutcome::Indeterminate;
    }
    if rhs.iter().any(|v| v == &lhs_str) {
        ConditionOutcome::Match
    } else {
        ConditionOutcome::NoMatch
    }
}

/// Strict numeric form: integers and decimals, signed or unsigned, with no
/// scientific notation, no hex literals, and no NaN or Infinity. Hand-rolled to
/// keep the evaluation hot path free of the regex crate
fn parse_numeric_rhs(s: &str) -> Option<f64> {
    let bytes = s.as_bytes();
    if bytes.is_empty() {
        return None;
    }
    let mut i = 0;
    if bytes[0] == b'-' {
        i += 1;
    }
    let int_start = i;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        i += 1;
    }
    let int_len = i - int_start;
    let mut had_dot = false;
    let mut had_frac = false;
    if i < bytes.len() && bytes[i] == b'.' {
        had_dot = true;
        i += 1;
        let frac_start = i;
        while i < bytes.len() && bytes[i].is_ascii_digit() {
            i += 1;
        }
        had_frac = i > frac_start;
    }
    if i != bytes.len() {
        return None;
    }
    let valid = matches!(
        (int_len > 0, had_dot, had_frac),
        (true, false, _) | (true, true, true) | (false, true, true)
    );
    if !valid {
        return None;
    }
    let parsed = s.parse::<f64>().ok()?;
    if parsed.is_finite() {
        Some(parsed)
    } else {
        None
    }
}

/// Numeric comparison. A non-numeric LHS or an empty RHS is `Indeterminate`. If
/// any RHS value parses and the comparison agrees, the result is `Match`. If no
/// value matched but at least one RHS string failed to parse, the result is
/// `Indeterminate` because the full RHS could not be checked. Only when every
/// RHS parsed and none matched is the result `NoMatch`.
///
/// A string LHS in the same strict numeric form the RHS accepts compares as its
/// numeric value. A standard attribute like `app_build` is an opaque string at
/// the context level (iOS `CFBundleVersion`, Android version code as a string),
/// so numeric operators apply to it when the string parses as a number. Any
/// other string stays `Indeterminate`
fn compare_number(
    lhs: &AttributeValue,
    rhs: &[String],
    cmp: impl Fn(f64, f64) -> bool,
) -> ConditionOutcome {
    let a = match lhs {
        AttributeValue::Number(n) => *n,
        AttributeValue::String(s) => match parse_numeric_rhs(s) {
            Some(n) => n,
            None => return ConditionOutcome::Indeterminate,
        },
        _ => return ConditionOutcome::Indeterminate,
    };
    if rhs.is_empty() {
        return ConditionOutcome::Indeterminate;
    }
    let mut any_parse_failure = false;
    for v in rhs {
        match parse_numeric_rhs(v) {
            Some(n) if cmp(a, n) => return ConditionOutcome::Match,
            Some(_) => continue,
            None => any_parse_failure = true,
        }
    }
    if any_parse_failure {
        ConditionOutcome::Indeterminate
    } else {
        ConditionOutcome::NoMatch
    }
}

/// String-predicate family (`contains`, `starts_with`, `ends_with`). A
/// non-string LHS or an empty RHS is `Indeterminate`
fn string_predicate(
    lhs: &AttributeValue,
    rhs: &[String],
    pred: impl Fn(&str, &str) -> bool,
) -> ConditionOutcome {
    let AttributeValue::String(a) = lhs else {
        return ConditionOutcome::Indeterminate;
    };
    if rhs.is_empty() {
        return ConditionOutcome::Indeterminate;
    }
    if rhs.iter().any(|needle| pred(a, needle)) {
        ConditionOutcome::Match
    } else {
        ConditionOutcome::NoMatch
    }
}

/// Semver-family comparison. A non-string LHS, an empty RHS, or a value that
/// cannot be parsed as a semantic version yields `Indeterminate` so a negated
/// semver check over a malformed value stays conservative
fn evaluate_semver(op: Operator, lhs: &AttributeValue, rhs: &[String]) -> ConditionOutcome {
    let AttributeValue::String(lhs_str) = lhs else {
        return ConditionOutcome::Indeterminate;
    };
    if rhs.is_empty() {
        return ConditionOutcome::Indeterminate;
    }
    let lhs_version = match semver::Version::parse(lhs_str) {
        Ok(mut v) => {
            v.build = semver::BuildMetadata::EMPTY;
            v
        }
        Err(error) => {
            tracing::debug!(value = lhs_str, %error, "semver lhs unparseable");
            return ConditionOutcome::Indeterminate;
        }
    };
    // The platform canonicalizes rule semver values on write, so the wire form
    // parses directly without re-coercion. Build metadata is stripped before
    // comparison because the semver standard ignores it for precedence. Rust's
    // `semver::Version` `Ord` includes build metadata, so metadata is cleared
    // on both sides before calling `cmp`
    use std::cmp::Ordering;
    let mut any_parse_failure = false;
    let mut any_match = false;
    for value in rhs {
        match semver::Version::parse(value) {
            Ok(mut rhs_version) => {
                rhs_version.build = semver::BuildMetadata::EMPTY;
                let cmp = lhs_version.cmp(&rhs_version);
                let result = match op {
                    Operator::SemVerEq => cmp == Ordering::Equal,
                    Operator::SemVerGt => cmp == Ordering::Greater,
                    Operator::SemVerGte => cmp != Ordering::Less,
                    Operator::SemVerLt => cmp == Ordering::Less,
                    Operator::SemVerLte => cmp != Ordering::Greater,
                    _ => false,
                };
                if result {
                    any_match = true;
                    break;
                }
            }
            Err(error) => {
                tracing::debug!(value, %error, "semver rhs unparseable");
                any_parse_failure = true;
            }
        }
    }
    if any_match {
        ConditionOutcome::Match
    } else if any_parse_failure {
        ConditionOutcome::Indeterminate
    } else {
        ConditionOutcome::NoMatch
    }
}

/// Condition-level check for whether an attribute is set.
///
/// Returns `false` for a missing attribute (the `None` case) and for an explicit
/// `AttributeValue::Null`. Every other variant counts as set, including empty
/// strings, whitespace-only strings, the numeric zero, `false`, and empty
/// arrays. The "set" semantic asks whether the developer supplied a non-null
/// value, not whether the value is truthy
pub fn is_set(attr: Option<&AttributeValue>) -> bool {
    !matches!(attr, None | Some(AttributeValue::Null))
}

pub fn is_not_set(attr: Option<&AttributeValue>) -> bool {
    !is_set(attr)
}
