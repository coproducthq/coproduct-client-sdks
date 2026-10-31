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
        Condition::Geofence {
            attribute,
            center_lat,
            center_lng,
            radius_m,
        } => evaluate_geofence(attribute, *center_lat, *center_lng, *radius_m, ctx),
        Condition::And { rules } => evaluate_and(rules, ctx, segments),
        Condition::Or { rules } => evaluate_or(rules, ctx, segments),
        Condition::Not { rule } => negate(evaluate_condition(rule, ctx, segments)),
        Condition::Unknown { tag } => {
            // An unknown node fails closed when reached. In the rule walker this
            // arm is normally pre-empted: the walker scans each rule for unknown
            // nodes up front and fails the whole flag closed before evaluating any
            // rule that carries one, so the fail-closed holds for every context
            // regardless of short-circuit order. This arm remains the backstop for
            // any direct evaluation and keeps the outcome total for an unknown node
            // reached mid-tree
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

/// Evaluate a circular geo-fence. The device point is read from `attribute` as a
/// `{lat,lng}` object; an absent or malformed point is Indeterminate (no location
/// to test, so the rule falls through rather than failing to a false negative),
/// consistent with how a missing attribute is Indeterminate for value operators.
fn evaluate_geofence(
    attribute: &str,
    center_lat: f64,
    center_lng: f64,
    radius_m: f64,
    ctx: &EvaluationContext,
) -> ConditionOutcome {
    match ctx.get_attribute(attribute).as_ref().and_then(point_latlng) {
        None => ConditionOutcome::Indeterminate,
        Some((lat, lng)) => {
            if crate::geo::haversine_meters(lat, lng, center_lat, center_lng) <= radius_m {
                ConditionOutcome::Match
            } else {
                ConditionOutcome::NoMatch
            }
        }
    }
}

/// Read a device location from a context attribute: a two-element numeric array
/// `[lat, lng]`. An array keeps the point strongly typed while riding the SDK's
/// existing number-array context value across the FFI, which has no object kind.
/// Returns `None` for anything that is not two finite numbers.
fn point_latlng(value: &crate::context::AttributeValue) -> Option<(f64, f64)> {
    use crate::context::AttributeValue;
    let AttributeValue::Array(items) = value else {
        return None;
    };
    let [AttributeValue::Number(lat), AttributeValue::Number(lng)] = items.as_slice() else {
        return None;
    };
    (lat.is_finite() && lng.is_finite()).then_some((*lat, *lng))
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
    match rule {
        SegmentRule::Attribute {
            attribute,
            operator,
            values,
        } => {
            let resolved = ctx.get_attribute(attribute);
            match operator {
                Operator::IsSet => bool_outcome(crate::operators::is_set(resolved.as_ref())),
                Operator::IsNotSet => bool_outcome(crate::operators::is_not_set(resolved.as_ref())),
                Operator::Unknown => ConditionOutcome::CircuitBreak,
                _ => match resolved {
                    None => ConditionOutcome::Indeterminate,
                    Some(lhs) => evaluate_operator(*operator, &lhs, values),
                },
            }
        }
        SegmentRule::Geofence {
            attribute,
            center_lat,
            center_lng,
            radius_m,
        } => evaluate_geofence(attribute, *center_lat, *center_lng, *radius_m, ctx),
        SegmentRule::Unknown { .. } => ConditionOutcome::CircuitBreak,
    }
}
