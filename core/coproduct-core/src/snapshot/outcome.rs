/// Tetra-state outcome of evaluating a condition or an operator.
///
/// `Indeterminate` is deliberately distinct from `NoMatch` so the condition
/// tree's `Not` combinator can preserve "could not evaluate" instead of
/// flipping it to a match. That distinction is what keeps a negated
/// missing-attribute check from including every user who never set the
/// attribute. `CircuitBreak` is reserved for an unknown operator or unknown
/// condition node, which fails the rule closed
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConditionOutcome {
    Match,
    NoMatch,
    Indeterminate,
    CircuitBreak,
}
