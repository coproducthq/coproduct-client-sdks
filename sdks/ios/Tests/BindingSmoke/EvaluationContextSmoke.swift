// Compiled (not executed) to prove the evaluation-context and attribute-value
// types exported over UniFFI are reachable from Swift with the expected shape.
// If this typechecks, the binding surface is correct

import Foundation

func proveEvaluationContextCompiles() {
    let ctx = EvaluationContextHandle(targetingKey: "user-123")
    let _: String = ctx.targetingKey()
    ctx.setAttribute(name: "plan", value: .string(value: "premium"))
    let _: AttributeValueFfi? = ctx.getAttribute(name: "plan")

    let _: AttributeValueFfi = .bool(value: true)
    let _: AttributeValueFfi = .number(value: 0.0)
    let _: AttributeValueFfi = .string(value: "x")
    let _: AttributeValueFfi = .null
}
