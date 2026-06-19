use coproduct_core::context::AttributeValue;
use coproduct_core::operators::{Operator, evaluate};
use coproduct_core::snapshot::ConditionOutcome;

fn rhs_for(op: Operator) -> Vec<String> {
    let strs: &[&str] = match op {
        Operator::Equals | Operator::NotEquals => &["x"],
        Operator::Gt | Operator::Gte | Operator::Lt | Operator::Lte => &["50"],
        Operator::In | Operator::NotIn => &["us", "ca"],
        Operator::StartsWith | Operator::EndsWith | Operator::Contains | Operator::NotContains => {
            &["a"]
        }
        Operator::SemVerEq
        | Operator::SemVerGt
        | Operator::SemVerGte
        | Operator::SemVerLt
        | Operator::SemVerLte => &["1.0.0"],
        Operator::IsSet | Operator::IsNotSet | Operator::Unknown => &[],
    };
    strs.iter().map(|s| s.to_string()).collect()
}

const COMPARISON_OPS: &[Operator] = &[
    Operator::Equals,
    Operator::NotEquals,
    Operator::Gt,
    Operator::Gte,
    Operator::Lt,
    Operator::Lte,
    Operator::In,
    Operator::NotIn,
    Operator::StartsWith,
    Operator::EndsWith,
    Operator::Contains,
    Operator::NotContains,
    Operator::SemVerEq,
    Operator::SemVerGt,
    Operator::SemVerGte,
    Operator::SemVerLt,
    Operator::SemVerLte,
];

#[test]
fn null_lhs_is_indeterminate_for_every_comparison_operator() {
    // The headline conservative-negation contract. IsSet and IsNotSet are
    // excluded because they are zero-value operators that observe a missing
    // attribute directly at the condition-tree layer and never reach evaluate
    // with an AttributeValue::Null
    let null = AttributeValue::Null;
    for op in COMPARISON_OPS {
        let r = rhs_for(*op);
        assert_eq!(
            evaluate(*op, &null, &r),
            ConditionOutcome::Indeterminate,
            "operator {op:?} must return Indeterminate for null lhs"
        );
    }
}

#[test]
fn empty_rhs_is_indeterminate_for_every_comparison_operator() {
    let lhs = AttributeValue::String("anything".to_string());
    let r: Vec<String> = vec![];
    for op in COMPARISON_OPS {
        assert_eq!(
            evaluate(*op, &lhs, &r),
            ConditionOutcome::Indeterminate,
            "operator {op:?} must return Indeterminate for empty rhs"
        );
    }
}

#[test]
fn object_lhs_is_indeterminate_for_every_comparison_operator() {
    // An object lhs cannot satisfy any string, number, or semver operator. It
    // stays Indeterminate rather than NoMatch so negation preserves the
    // conservative semantics
    let obj = AttributeValue::Object(Default::default());
    for op in COMPARISON_OPS {
        let r = rhs_for(*op);
        assert_eq!(
            evaluate(*op, &obj, &r),
            ConditionOutcome::Indeterminate,
            "operator {op:?} must return Indeterminate for object lhs"
        );
    }
}

#[test]
fn array_lhs_is_indeterminate_for_every_comparison_operator() {
    // Arrays are valid on the rhs of in and not_in but never on the lhs.
    // Indeterminate uniformly across all comparison operators
    let arr = AttributeValue::Array(vec![AttributeValue::String("us".to_string())]);
    for op in COMPARISON_OPS {
        let r = rhs_for(*op);
        assert_eq!(
            evaluate(*op, &arr, &r),
            ConditionOutcome::Indeterminate,
            "operator {op:?} must return Indeterminate for array lhs"
        );
    }
}

#[test]
fn unknown_operator_circuit_breaks_at_dispatch() {
    // The forward-compat catch-all for an operator name from a newer server. The
    // condition tree normally short-circuits before calling evaluate, but if one
    // arrives here the dispatcher fails closed rather than pretending to evaluate
    let lhs = AttributeValue::String("anything".to_string());
    let r: Vec<String> = vec![];
    assert_eq!(
        evaluate(Operator::Unknown, &lhs, &r),
        ConditionOutcome::CircuitBreak
    );
}
