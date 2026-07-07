//! Condition-tree evaluation.
//!
//! Walks the wire-format `Condition` tree from `snapshot::rule` and produces a
//! tetra-state `ConditionOutcome`. The `Not` combinator preserves
//! `Indeterminate` so a negation over data that could not be evaluated does not
//! flip to a match, which is what keeps a negated missing-attribute check from
//! including every user who never set the attribute

use std::collections::HashMap;

use crate::context::EvaluationContext;
use crate::operators::{Operator, evaluate as evaluate_operator};
use crate::snapshot::{Condition, ConditionOutcome, Segment, SegmentRule};

/// Evaluate one condition node against a held context and the segment table.
///
/// Combinator semantics:
/// - `Not` flips Match and NoMatch, and preserves Indeterminate and CircuitBreak
/// - `And` returns Match when all children match, short-circuits to NoMatch on
///   any NoMatch and to CircuitBreak on any CircuitBreak, otherwise propagates
///   Indeterminate
/// - `Or` short-circuits to Match on any Match and to CircuitBreak on any
///   CircuitBreak, returns NoMatch when all children are NoMatch, otherwise
///   propagates Indeterminate
pub fn evaluate_condition(
    cond: &Condition,
    ctx: &EvaluationContext,
    segments: &HashMap<String, Segment>,
) -> ConditionOutcome {
    match cond {
        Condition::Always => ConditionOutcome::Match,
        Condition::Attribute {
            attribute,
            operator,
            values,
        } => evaluate_attribute(attribute, *operator, values, ctx),
        Condition::Segment { segment_key } => resolve_segment(segment_key, ctx, segments),
        Condition::And { rules } => evaluate_and(rules, ctx, segments),
        Condition::Or { rules } => evaluate_or(rules, ctx, segments),
        Condition::Not { rule } => negate(evaluate_condition(rule, ctx, segments)),
        Condition::Unknown { tag } => {
            // An unknown node fails closed when reached. Because `And` / `Or`
            // short-circuit, an unknown child is only reached for contexts not
            // short-circuited first, so this fail-closed is per-context. Strict
            // fail-closed (unknown anywhere in a matched rule fails the whole flag)
            // lands as a separate change
            tracing::error!(node_tag = %tag, "RULE_CIRCUIT_BREAK on unknown condition node");
            ConditionOutcome::CircuitBreak
        }
    }
}

fn evaluate_attribute(
    attribute: &str,
    operator: Operator,
    values: &[String],
    ctx: &EvaluationContext,
) -> ConditionOutcome {
    // is_set and is_not_set are zero-value operators that must observe a missing
    // attribute as `None`, so they take the resolved option directly and are
    // total (always Match or NoMatch, never Indeterminate)
    let resolved = ctx.get_attribute(attribute);
    match operator {
        Operator::IsSet => bool_outcome(crate::operators::is_set(resolved.as_ref())),
        Operator::IsNotSet => bool_outcome(crate::operators::is_not_set(resolved.as_ref())),
        Operator::Unknown => ConditionOutcome::CircuitBreak,
        _ => match resolved {
            None => ConditionOutcome::Indeterminate,
            Some(lhs) => evaluate_operator(operator, &lhs, values),
        },
    }
}

fn bool_outcome(matched: bool) -> ConditionOutcome {
    if matched {
        ConditionOutcome::Match
    } else {
        ConditionOutcome::NoMatch
    }
}

fn negate(outcome: ConditionOutcome) -> ConditionOutcome {
    match outcome {
        ConditionOutcome::Match => ConditionOutcome::NoMatch,
        ConditionOutcome::NoMatch => ConditionOutcome::Match,
        ConditionOutcome::Indeterminate => ConditionOutcome::Indeterminate,
        ConditionOutcome::CircuitBreak => ConditionOutcome::CircuitBreak,
    }
}

fn evaluate_and(
    rules: &[Condition],
    ctx: &EvaluationContext,
    segments: &HashMap<String, Segment>,
) -> ConditionOutcome {
    let mut indeterminate_seen = false;
    for child in rules {
        match evaluate_condition(child, ctx, segments) {
            ConditionOutcome::Match => continue,
            ConditionOutcome::NoMatch => return ConditionOutcome::NoMatch,
            ConditionOutcome::CircuitBreak => return ConditionOutcome::CircuitBreak,
            ConditionOutcome::Indeterminate => indeterminate_seen = true,
        }
    }
    if indeterminate_seen {
        ConditionOutcome::Indeterminate
    } else {
        ConditionOutcome::Match
    }
}

fn evaluate_or(
    rules: &[Condition],
    ctx: &EvaluationContext,
    segments: &HashMap<String, Segment>,
) -> ConditionOutcome {
    let mut indeterminate_seen = false;
    for child in rules {
        match evaluate_condition(child, ctx, segments) {
            ConditionOutcome::Match => return ConditionOutcome::Match,
            ConditionOutcome::CircuitBreak => return ConditionOutcome::CircuitBreak,
            ConditionOutcome::NoMatch => continue,
            ConditionOutcome::Indeterminate => indeterminate_seen = true,
        }
    }
    if indeterminate_seen {
        ConditionOutcome::Indeterminate
    } else {
        ConditionOutcome::NoMatch
    }
}

/// Resolve a segment reference. A missing segment is a data condition, not an
/// evaluation uncertainty: the user is definitively not a member of a segment
/// that does not exist, so this returns NoMatch (not Indeterminate) and logs a
/// warning. Segment rules resolve with OR semantics across the rules
fn resolve_segment(
    key: &str,
    ctx: &EvaluationContext,
    segments: &HashMap<String, Segment>,
) -> ConditionOutcome {
    let segment = match segments.get(key) {
        Some(s) => s,
        None => {
            tracing::warn!(
                segment_key = key,
                "segment not found in snapshot, treating as no-match"
            );
            return ConditionOutcome::NoMatch;
        }
    };
    let mut indeterminate_seen = false;
    for rule in &segment.rules {
        match evaluate_segment_rule(rule, ctx) {
            ConditionOutcome::Match => return ConditionOutcome::Match,
            ConditionOutcome::CircuitBreak => return ConditionOutcome::CircuitBreak,
            ConditionOutcome::NoMatch => continue,
            ConditionOutcome::Indeterminate => indeterminate_seen = true,
        }
    }
    if indeterminate_seen {
        ConditionOutcome::Indeterminate
    } else {
        ConditionOutcome::NoMatch
    }
}

/// Evaluate one flat segment rule. Same dispatch shape as an attribute
/// condition: zero-value operators take the resolved option, an unknown operator
/// circuit-breaks, and every other operator routes through the shared dispatcher
fn evaluate_segment_rule(rule: &SegmentRule, ctx: &EvaluationContext) -> ConditionOutcome {
    let resolved = ctx.get_attribute(&rule.attribute);
    match rule.operator {
        Operator::IsSet => bool_outcome(crate::operators::is_set(resolved.as_ref())),
        Operator::IsNotSet => bool_outcome(crate::operators::is_not_set(resolved.as_ref())),
        Operator::Unknown => ConditionOutcome::CircuitBreak,
        _ => match resolved {
            None => ConditionOutcome::Indeterminate,
            Some(lhs) => evaluate_operator(rule.operator, &lhs, &rule.values),
        },
    }
}
