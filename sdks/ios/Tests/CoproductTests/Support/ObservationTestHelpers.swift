@testable import Coproduct

// Test-only delivery hooks for the observation types. They live in the test
// target, not in Sources, and reach the internal push and merge through
// @testable import. Both drive the same subject the live core subscription
// feeds, so reactive code can be exercised without a running default instance

extension FlagObservation {
    func testOnlyPush(_ value: T) {
        push(value)
    }

    func testOnlySeed(_ value: T) {
        seed(value)
    }
}

extension FlagBundleObservation {
    func testOnlyMerge(key: String, value: FlagDetailValue) {
        merge(key: key, value: value)
    }

    func testOnlySeed(key: String, value: FlagDetailValue) {
        seed(key: key, value: value)
    }
}
