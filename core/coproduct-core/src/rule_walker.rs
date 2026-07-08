use std::collections::HashMap;

use crate::bucketing::bucket_for_vectors;
use crate::condition::evaluate_condition;
use crate::context::EvaluationContext;
use crate::snapshot::{
    ConditionOutcome, Flag, Rollout, Segment, TargetingRule, condition_contains_unknown,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuleWalkResult {
    /// A rule matched and its coverage gate included the user
    Match { rule_id: String, variation: String },
    /// No rule both matched and included the user via its coverage gate. The
    /// caller serves the fallthrough variation
    Fallthrough,
    /// A rule's condition tree contained an unknown node, or evaluating a
    /// condition reached a malformed or unsupported path, tripping
    /// RULE_CIRCUIT_BREAK. The unknown-node case is caught by the up-front scan
    /// before any condition is evaluated. The caller serves the off variation
    CircuitBreak,
}

/// Walk targeting rules top to bottom with the two-bucket coverage gate. The
/// first rule whose condition evaluates Match and whose rollout bucket lands
/// below `coverage` wins. The variant bucket picks among weighted rollouts.
/// Conditions that evaluate NoMatch or Indeterminate (missing attribute,
/// conservative negation, missing segment) continue the walk.
///
/// A flag fails closed on a circuit break in two ways. A rule whose condition tree
/// contains an unknown node anywhere fails the whole flag closed up front, before
/// any rule is evaluated, so the break holds for every context regardless of rule
/// order or short-circuit evaluation. This is computed from the flag on each walk,
/// so it holds no matter how the flag was constructed, not only for flags that
/// went through snapshot ingestion. Separately, a CircuitBreak that surfaces while
/// actually evaluating a condition also fails the flag closed. With the up-front
/// scan in place, that second path now only covers breaks not caused by an unknown
/// node, such as an unknown operator on an otherwise valid attribute condition
///
/// An empty targeting key skips all targeting rules and serves the fallthrough:
/// there is no identity to bucket, so this is a deliberate "no targeting without
/// identity" policy. The client rejects an empty key upstream, so this guards a
/// context built without one
pub fn walk_rules(
    flag: &Flag,
    ctx: &EvaluationContext,
    segments: &HashMap<String, Segment>,
) -> RuleWalkResult {
    // Strict fail-closed: if any targeting rule's condition tree contains an
    // unknown node, the whole flag fails closed before we evaluate a single rule.
    // The scan runs up front, ahead of the walk, so the break holds for every
    // context, including one that would have matched an earlier valid rule and
    // one whose evaluation would short-circuit past the unknown child. This is the
    // whole-flag strict variant of the per-context break that `evaluate_condition`
    // returns when the walk actually reaches an unknown node. The scan is cheap
    // next to the condition evaluation and per-rule bucketing that follow, and
    // computing it here rather than caching it on the rule keeps the guarantee
    // true for any flag the walker is handed, however it was built
    if flag
        .targeting_rules
        .iter()
        .any(|rule| condition_contains_unknown(&rule.condition))
    {
        return RuleWalkResult::CircuitBreak;
    }
    let targeting_key = ctx.targeting_key();
    if targeting_key.is_empty() {
        return RuleWalkResult::Fallthrough;
    }
    for rule in &flag.targeting_rules {
        match evaluate_condition(&rule.condition, ctx, segments) {
            // Indeterminate is treated identically to NoMatch at the rule-walker
            // boundary: the rule does not include the user, so continue. The
            // distinction matters only inside the condition tree
            ConditionOutcome::NoMatch | ConditionOutcome::Indeterminate => continue,
            ConditionOutcome::CircuitBreak => return RuleWalkResult::CircuitBreak,
            ConditionOutcome::Match => {
                if let Some(variation) = apply_coverage_and_rollout(rule, targeting_key) {
                    return RuleWalkResult::Match {
                        rule_id: rule.rule_id.clone(),
                        variation,
                    };
                }
            }
        }
    }
    RuleWalkResult::Fallthrough
}

fn apply_coverage_and_rollout(rule: &TargetingRule, targeting_key: &str) -> Option<String> {
    let rollout_bucket = bucket_for_vectors(&rule.rule_id, targeting_key, "rollout");
    if rollout_bucket >= rule.coverage.0 {
        return None;
    }
    match &rule.rollout {
        Rollout::Variation { variation } => Some(variation.clone()),
        Rollout::Weights { weights } => {
            let variant_bucket = bucket_for_vectors(&rule.rule_id, targeting_key, "variant");
            let mut cursor: u32 = 0;
            for w in weights {
                // The bucket lives in 0..=9999 basis points and percentages live
                // in 0..=100. Lift the percentage into basis points so the gate
                // compares like with like
                cursor = cursor.saturating_add(w.percentage.saturating_mul(100));
                if variant_bucket < cursor {
                    return Some(w.variation_key.clone());
                }
            }
            // The server validates that weights sum to 100, so the cursor reaches
            // 10000 before the loop ends. This fall-through fires only on a
            // corrupt snapshot and yields no assignment, treated as out of coverage
            None
        }
        // An unrecognized rollout shape cannot assign a variation, so the user is
        // treated as out of coverage and the walk continues
        Rollout::Unknown => None,
    }
}
