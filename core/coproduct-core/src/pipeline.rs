use std::collections::HashMap;

use crate::error::EvaluationErrorCode;

/// Result of a single flag evaluation. Carried through the pipeline and returned
/// to the typed getters. `value_label` is a stable string form of the value used
/// for memoization equality across recursive prerequisite descents. The typed
/// value travels separately on the public surface
#[derive(Debug, Clone)]
pub struct EvaluationOutcome {
    pub variation_key: Option<String>,
    pub value_label: String,
    pub reason: EvaluationReason,
    pub error_code: Option<EvaluationErrorCode>,
    pub error_message: Option<String>,
}

impl EvaluationOutcome {
    pub fn resolved(variation_key: &str, value_label: &str) -> Self {
        Self {
            variation_key: Some(variation_key.to_string()),
            value_label: value_label.to_string(),
            reason: EvaluationReason::TargetingMatch,
            error_code: None,
            error_message: None,
        }
    }

    pub fn default_with_error(code: EvaluationErrorCode, message: &str) -> Self {
        Self {
            variation_key: None,
            value_label: String::new(),
            reason: EvaluationReason::Error,
            error_code: Some(code),
            error_message: Some(message.to_string()),
        }
    }
}

/// The reason an evaluation resolved the way it did. `Off` covers isPaused,
/// enabled=false, and the RULE_CIRCUIT_BREAK-to-offVariation path
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvaluationReason {
    TargetingMatch,
    Fallthrough,
    Off,
    PrerequisiteFailed,
    Error,
}

/// State of a flag inside the per-evaluation `VisitingSet`. `Visiting` is the
/// cycle-detection sentinel placed before descending into a flag. `Resolved` is
/// the memoized outcome reused for diamond dependencies
#[derive(Debug, Clone)]
pub enum VisitingState {
    Visiting,
    Resolved(EvaluationOutcome),
}

/// Per-top-level-evaluation visit tracker. Scoped to one outer getter call and
/// never shared across concurrent evaluations, which is what makes the
/// cycle-detection sentinel correct
#[derive(Debug, Default)]
pub struct VisitingSet {
    inner: HashMap<String, VisitingState>,
}

impl VisitingSet {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }

    pub fn len(&self) -> usize {
        self.inner.len()
    }

    pub fn mark_visiting(&mut self, flag_key: &str) {
        self.inner
            .insert(flag_key.to_string(), VisitingState::Visiting);
    }

    pub fn resolve(&mut self, flag_key: &str, outcome: EvaluationOutcome) {
        self.inner
            .insert(flag_key.to_string(), VisitingState::Resolved(outcome));
    }

    pub fn get(&self, flag_key: &str) -> Option<&VisitingState> {
        self.inner.get(flag_key)
    }

    pub fn is_visiting(&self, flag_key: &str) -> bool {
        matches!(self.inner.get(flag_key), Some(VisitingState::Visiting))
    }
}

use crate::context::EvaluationContext;
use crate::hooks::{HookContext, HookOutcome, HookRegistry};
use crate::snapshot::{Flag, IndexedSnapshot};

/// Prerequisite depth cap. The counter starts at 0 at the top-level call. Five
/// recursive prerequisite descents are permitted (the counter reaches 5). A
/// sixth descent trips RULE_CIRCUIT_BREAK and serves the off variation
pub const MAX_PREREQ_DEPTH: u32 = 5;

/// Recursively evaluate a flag through the full pipeline. This shell wires the
/// depth guard, the hook firing skeleton, and the memoization read. The numbered
/// steps are filled into `run_pipeline_body`
pub fn evaluate_recursive(
    snapshot: &IndexedSnapshot,
    flag_key: &str,
    ctx: &EvaluationContext,
    hooks: &HookRegistry,
    visiting: &mut VisitingSet,
    depth: u32,
) -> EvaluationOutcome {
    let hook_ctx = HookContext {
        flag_key,
        default_value_label: "",
    };

    fire_before(hooks, &hook_ctx);

    let outcome = if depth > MAX_PREREQ_DEPTH {
        circuit_break_off(
            snapshot,
            flag_key,
            "prerequisite chain exceeded the depth cap",
        )
    } else if let Some(VisitingState::Resolved(memo)) = visiting.get(flag_key).cloned() {
        memo
    } else {
        run_pipeline_body(snapshot, flag_key, ctx, hooks, visiting, depth)
    };

    fire_after(hooks, &hook_ctx, &outcome);

    outcome
}

/// Fire the before callback on every hook in registration order
fn fire_before(hooks: &HookRegistry, hook_ctx: &HookContext<'_>) {
    for hook in hooks.iter() {
        match hook.before(hook_ctx) {
            HookOutcome::Proceed => (),
        }
    }
}

/// Fire the error-or-after callback then finally on every hook. The error arm
/// runs when the outcome carries an error code, otherwise the after arm runs
fn fire_after(hooks: &HookRegistry, hook_ctx: &HookContext<'_>, outcome: &EvaluationOutcome) {
    for hook in hooks.iter() {
        match outcome.error_code {
            Some(code) => hook.error(
                hook_ctx,
                code,
                outcome.error_message.as_deref().unwrap_or(""),
            ),
            None => hook.after(hook_ctx, outcome.variation_key.as_deref().unwrap_or("")),
        }
        hook.finally(hook_ctx);
    }
}

/// Fire the full hook bracket for a terminal outcome that short-circuits before
/// the recursive body runs, so the early pipeline steps still see before, error,
/// and finally
fn fire_terminal(
    hooks: &HookRegistry,
    hook_ctx: &HookContext<'_>,
    outcome: EvaluationOutcome,
) -> EvaluationOutcome {
    fire_before(hooks, hook_ctx);
    fire_after(hooks, hook_ctx, &outcome);
    outcome
}

fn circuit_break_off(
    snapshot: &IndexedSnapshot,
    flag_key: &str,
    message: &str,
) -> EvaluationOutcome {
    // The off variation key is nullable in the wire schema. When absent, fall
    // back to the conventional `off` key
    let off_variation_key = snapshot
        .flags
        .get(flag_key)
        .and_then(|f| f.off_variation.clone())
        .unwrap_or_else(|| "off".to_string());
    let value_label = snapshot
        .flags
        .get(flag_key)
        .and_then(|f| f.variations.iter().find(|v| v.key == off_variation_key))
        .map(|v| v.value.label())
        .unwrap_or_else(|| "false".to_string());

    EvaluationOutcome {
        variation_key: Some(off_variation_key),
        value_label,
        reason: EvaluationReason::Off,
        error_code: Some(EvaluationErrorCode::RuleCircuitBreak),
        error_message: Some(message.to_string()),
    }
}

fn run_pipeline_body(
    snapshot: &IndexedSnapshot,
    flag_key: &str,
    ctx: &EvaluationContext,
    hooks: &HookRegistry,
    visiting: &mut VisitingSet,
    depth: u32,
) -> EvaluationOutcome {
    let Some(flag) = snapshot.flags.get(flag_key) else {
        return EvaluationOutcome::default_with_error(
            EvaluationErrorCode::FlagNotFound,
            "flag not in snapshot",
        );
    };

    // The isPaused kill switch and the enabled=false environment gate. Both route
    // through `should_serve_off` so the conformance harness and the production
    // pipeline validate the same predicate
    if crate::variation_select::should_serve_off(flag).is_some() {
        // The off-serve outcome is deterministic, so memoize it like every other
        // body exit. This lets a paused or disabled flag reached twice through a
        // diamond prerequisite reuse the result instead of re-running
        let outcome = serve_variation(
            flag,
            flag.off_variation.as_deref().unwrap_or("off"),
            EvaluationReason::Off,
            None,
            None,
        );
        visiting.resolve(flag_key, outcome.clone());
        return outcome;
    }

    // Prerequisites. Mark this flag on the descent stack first so a cycle through
    // it is detected while its prereqs evaluate
    visiting.mark_visiting(flag_key);
    for prereq in flag.prerequisites.iter() {
        match check_prerequisite(snapshot, flag, prereq, ctx, hooks, visiting, depth) {
            PrereqOutcome::Satisfied => continue,
            PrereqOutcome::Failed => {
                let outcome = serve_variation(
                    flag,
                    flag.off_variation.as_deref().unwrap_or("off"),
                    EvaluationReason::PrerequisiteFailed,
                    None,
                    None,
                );
                visiting.resolve(flag_key, outcome.clone());
                return outcome;
            }
            PrereqOutcome::CircuitBreak(message) => {
                let outcome = circuit_break_off(snapshot, flag_key, &message);
                visiting.resolve(flag_key, outcome.clone());
                return outcome;
            }
        }
    }

    // Walk targeting rules top to bottom. The walker needs the snapshot segments
    // map so segment-membership conditions resolve. A matched rule carries the
    // rollout-selected variation, which we serve or absorb into the off variation
    // when the variation reference is dangling
    use crate::rule_walker::{RuleWalkResult, walk_rules};
    let outcome = match walk_rules(flag, ctx, &snapshot.segments) {
        RuleWalkResult::Match { variation, .. } => serve_matched_rule_or_absorb(flag, &variation),
        RuleWalkResult::CircuitBreak => circuit_break_off(
            snapshot,
            flag_key,
            "rule walker encountered an unknown operator or malformed node",
        ),
        RuleWalkResult::Fallthrough => serve_fallthrough_or_circuit_break(flag),
    };
    visiting.resolve(flag_key, outcome.clone());
    outcome
}

enum PrereqOutcome {
    Satisfied,
    Failed,
    CircuitBreak(String),
}

#[allow(clippy::too_many_arguments)]
fn check_prerequisite(
    snapshot: &IndexedSnapshot,
    parent: &Flag,
    prereq: &crate::snapshot::Prerequisite,
    ctx: &EvaluationContext,
    hooks: &HookRegistry,
    visiting: &mut VisitingSet,
    depth: u32,
) -> PrereqOutcome {
    // Cycle: the prereq is already on the descent stack
    if visiting.is_visiting(&prereq.flag_key) {
        tracing::warn!(
            parent_flag = parent.key.as_str(),
            prereq_flag = prereq.flag_key.as_str(),
            "prerequisite cycle detected"
        );
        return PrereqOutcome::CircuitBreak(format!(
            "prereq cycle detected at {}",
            prereq.flag_key
        ));
    }

    // Missing prereq flag: treat as failed
    let Some(prereq_flag) = snapshot.flags.get(&prereq.flag_key) else {
        tracing::warn!(
            parent_flag = parent.key.as_str(),
            prereq_flag = prereq.flag_key.as_str(),
            "prerequisite flag not in snapshot, treating as failed"
        );
        return PrereqOutcome::Failed;
    };

    // Required variation does not exist on the prereq flag: treat as failed
    if !prereq_flag
        .variations
        .iter()
        .any(|v| v.key == prereq.variation)
    {
        tracing::warn!(
            parent_flag = parent.key.as_str(),
            prereq_flag = prereq.flag_key.as_str(),
            required_variation = prereq.variation.as_str(),
            "prerequisite required variation does not exist, treating as failed"
        );
        return PrereqOutcome::Failed;
    }

    // Recursively evaluate the prereq flag through its own full pipeline
    let resolved = evaluate_recursive(snapshot, &prereq.flag_key, ctx, hooks, visiting, depth + 1);

    if let Some(EvaluationErrorCode::RuleCircuitBreak) = resolved.error_code {
        return PrereqOutcome::CircuitBreak(
            resolved
                .error_message
                .unwrap_or_else(|| "prereq circuit-break".to_string()),
        );
    }

    match resolved.variation_key {
        Some(v) if v == prereq.variation => PrereqOutcome::Satisfied,
        _ => PrereqOutcome::Failed,
    }
}

pub(crate) fn serve_fallthrough_or_circuit_break(flag: &Flag) -> EvaluationOutcome {
    match &flag.fallthrough_variation {
        Some(key) => serve_variation(flag, key, EvaluationReason::Fallthrough, None, None),
        None => serve_variation(
            flag,
            flag.off_variation.as_deref().unwrap_or("off"),
            EvaluationReason::Off,
            Some(EvaluationErrorCode::RuleCircuitBreak),
            Some("fallthroughVariation is null"),
        ),
    }
}

pub(crate) fn serve_variation(
    flag: &Flag,
    variation_key: &str,
    reason: EvaluationReason,
    error_code: Option<EvaluationErrorCode>,
    error_message: Option<&str>,
) -> EvaluationOutcome {
    let value_label = flag
        .variations
        .iter()
        .find(|v| v.key == variation_key)
        .map(|v| v.value.label())
        .unwrap_or_default();
    EvaluationOutcome {
        variation_key: Some(variation_key.to_string()),
        value_label,
        reason,
        error_code,
        error_message: error_message.map(str::to_string),
    }
}

/// Serve a matched rule's selected variation, or absorb a dangling reference
/// into the off variation.
///
/// A targeting rule whose rollout names a variation that no longer exists
/// resolves to the off variation rather than an error. This is distinct from
/// `RuleWalkResult::CircuitBreak`, which fires for an unknown operator or a
/// malformed node, not for a dangling variation reference. The absorber covers
/// matched rule rollouts only. A null or dangling fallthrough stays on the
/// RULE_CIRCUIT_BREAK path in `serve_fallthrough_or_circuit_break`
pub(crate) fn serve_matched_rule_or_absorb(flag: &Flag, variation_key: &str) -> EvaluationOutcome {
    if flag.variations.iter().any(|v| v.key == variation_key) {
        return serve_variation(
            flag,
            variation_key,
            EvaluationReason::TargetingMatch,
            None,
            None,
        );
    }
    tracing::warn!(
        flag_key = %flag.key,
        missing_variation = %variation_key,
        "matched rule references a missing variation, resolving to the off variation",
    );
    let off_key = flag.off_variation.as_deref().unwrap_or("off");
    serve_variation(flag, off_key, EvaluationReason::Off, None, None)
}

use crate::snapshot::FlagType;

/// Which typed getter invoked the pipeline. `Int` and `Number` both map to the
/// wire `NUMBER` flag type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequestedType {
    Bool,
    String,
    Int,
    Number,
    Json,
}

impl RequestedType {
    fn matches(self, flag_type: FlagType) -> bool {
        matches!(
            (self, flag_type),
            (Self::Bool, FlagType::Bool)
                | (Self::String, FlagType::String)
                | (Self::Int, FlagType::Number)
                | (Self::Number, FlagType::Number)
                | (Self::Json, FlagType::Json)
        )
    }
}

/// Top-level pipeline entry point. `snapshot = None` means no snapshot has
/// loaded yet (step 1). Steps 2 and 3 reject a missing flag and a type mismatch
/// before the recursive body runs
pub fn evaluate(
    snapshot: Option<&IndexedSnapshot>,
    flag_key: &str,
    requested_type: RequestedType,
    ctx: &EvaluationContext,
    hooks: &HookRegistry,
) -> EvaluationOutcome {
    // Steps 1-3 short-circuit before the recursive body, so they fire their own
    // full hook bracket. The recursive path fires its bracket inside
    // evaluate_recursive, so a normal evaluation is never double-fired
    let hook_ctx = HookContext {
        flag_key,
        default_value_label: "",
    };

    let Some(snapshot) = snapshot else {
        return fire_terminal(
            hooks,
            &hook_ctx,
            EvaluationOutcome::default_with_error(
                EvaluationErrorCode::ProviderNotReady,
                "SDK not started or no snapshot loaded",
            ),
        );
    };

    let Some(flag) = snapshot.flags.get(flag_key) else {
        return fire_terminal(
            hooks,
            &hook_ctx,
            EvaluationOutcome::default_with_error(
                EvaluationErrorCode::FlagNotFound,
                "flag not in snapshot",
            ),
        );
    };

    if !requested_type.matches(flag.r#type) {
        return fire_terminal(
            hooks,
            &hook_ctx,
            EvaluationOutcome::default_with_error(
                EvaluationErrorCode::TypeMismatch,
                "flag type does not match the requested getter",
            ),
        );
    }

    let mut visiting = VisitingSet::new();
    evaluate_recursive(snapshot, flag_key, ctx, hooks, &mut visiting, 0)
}
