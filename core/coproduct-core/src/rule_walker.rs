use std::collections::HashMap;

use crate::bucketing::bucket_for_vectors;
use crate::condition::evaluate_condition;
use crate::context::EvaluationContext;
use crate::snapshot::{ConditionOutcome, Flag, Rollout, Segment, TargetingRule};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuleWalkResult {
    /// A rule matched and its coverage gate included the user
    Match { rule_id: String, variation: String },
    /// No rule both matched and included the user via its coverage gate. The
    /// caller serves the fallthrough variation
    Fallthrough,
    /// An unknown node or malformed subtree tripped RULE_CIRCUIT_BREAK inside a
    /// condition. The caller serves the off variation
    CircuitBreak,
}

/// Walk targeting rules top to bottom with the two-bucket coverage gate. The
/// first rule whose condition evaluates Match and whose rollout bucket lands
/// below `coverage` wins. The variant bucket picks among weighted rollouts.
/// Conditions that evaluate NoMatch or Indeterminate (missing attribute,
/// conservative negation, missing segment) continue the walk. A condition that
/// evaluates CircuitBreak fails the whole flag closed
pub fn walk_rules(
    flag: &Flag,
    ctx: &EvaluationContext,
    segments: &HashMap<String, Segment>,
) -> RuleWalkResult {
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
