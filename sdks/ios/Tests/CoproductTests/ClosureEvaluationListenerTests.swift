import XCTest
@testable import Coproduct

final class ClosureEvaluationListenerTests: XCTestCase {
    func testClosureEvaluationListenerForwardsEventToClosure() {
        var received: EvaluationEvent?
        let listener = ClosureEvaluationListener { event in
            received = event
        }

        let event = EvaluationEvent(
            flagKey: "new-checkout",
            flagType: .bool,
            value: .bool(value: true),
            defaultValue: .bool(value: false),
            variant: "treatment",
            reason: .targetingMatch,
            ruleId: "rule-1",
            errorCode: nil,
            evaluatedAt: "2026-10-30T00:00:00Z"
        )

        listener.onEvaluation(event: event)

        XCTAssertEqual(received, event)
    }

    func testSetEvaluationListenerIsReachable() {
        // Compile-time check that the static entry point exists with the
        // expected signature. Not invoked here since it requires a live
        // default instance; runtime wiring is exercised by the generated
        // EvaluationListener protocol conformance above
        let _: (@escaping @Sendable (EvaluationEvent) -> Void) -> Void = Coproduct.setEvaluationListener
    }
}
