@testable import Coproduct

// Test-only delivery hooks for the observation types. They live in the test
// target, not in Sources, and reach the internal push and replace through
// @testable import. Both drive the same subject the live drain task feeds, so
// reactive code can be exercised without a running default instance

extension FlagObservation {
    func testOnlyPush(_ value: T) {
        push(value)
    }
}

extension FlagBundleObservation {
    func testOnlyReplace(with snapshot: [String: FlagDetailValue]) {
        replace(with: snapshot)
    }
}
