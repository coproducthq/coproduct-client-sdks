import XCTest
@testable import Coproduct

// Unavailable is the transport's way of saying a key has no usable value, and
// every observation resolves it to the caller's own default rather than to a type
// zero. These drive the observation types directly, the way the drain task feeds
// them, so they pin the mapping without a running default instance
final class ObservationUnavailableTests: XCTestCase {
    func testSingleKeyUnavailableResolvesToTheCallerDefault() {
        // The registration maps a nil seed to the default before constructing the
        // observation, which is the same mapping the drain applies to a delivery
        let seeded: Bool? = nil
        let observation = FlagObservation<Bool>(key: "flag", initial: seeded ?? true)
        XCTAssertEqual(observation.current, true, "an unavailable seed serves the default")

        let delivered: Bool? = nil
        observation.testOnlyPush(delivered ?? true)
        XCTAssertEqual(observation.current, true, "an unavailable delivery serves the default")
    }

    func testBundleDropsAKeyThatBecomesUnavailable() {
        let observation = FlagBundleObservation(
            keys: ["a", "b"],
            initial: ["a": .bool(true), "b": .bool(true)]
        )
        // A complete batch in which "b" is unavailable, mapped the way the
        // registration maps it
        observation.testOnlyReplace(with: ["a": .bool(false)])
        XCTAssertEqual(observation.current["a"], .bool(false))
        XCTAssertNil(observation.current["b"], "an unavailable key leaves the public dictionary")
    }

    func testBundleDeliveryReplacesRatherThanMergesAcrossBatches() {
        // A stale key must not survive a batch that no longer carries it, which is
        // what made per-key merging unsafe once batches became full state
        let observation = FlagBundleObservation(keys: ["a"], initial: ["a": .bool(true), "gone": .string("x")])
        observation.testOnlyReplace(with: ["a": .bool(true)])
        XCTAssertNil(observation.current["gone"])
    }
}
