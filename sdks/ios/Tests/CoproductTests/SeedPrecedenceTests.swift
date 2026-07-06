import XCTest
@testable import Coproduct

// A subscription-time seed must never overwrite a value a real change already
// delivered. Observations register the observer before reading the seed, so a
// change that lands during setup is delivered through push/merge; the seed then
// has to yield to it. These drive the seed and delivery paths directly to pin
// that precedence without depending on a timing race.
final class SeedPrecedenceTests: XCTestCase {
    func testSingleKeyDeliveredValueSurvivesLaterSeed() {
        let observation = FlagObservation<Bool>(key: "flag", initial: false)
        // A real change arrives first (observer already registered)
        observation.testOnlyPush(true)
        // The seed reads a stale value and must be dropped
        observation.testOnlySeed(false)
        XCTAssertEqual(observation.current, true, "a delivered value wins over a later seed")
    }

    func testSingleKeyDeliveryAfterSeedStillWins() {
        let observation = FlagObservation<Bool>(key: "flag", initial: false)
        observation.testOnlySeed(false)
        observation.testOnlyPush(true)
        XCTAssertEqual(observation.current, true, "a delivery always applies, even after a seed")
    }

    func testSingleKeySeedAppliesWhenNothingDelivered() {
        let observation = FlagObservation<Bool>(key: "flag", initial: false)
        observation.testOnlySeed(true)
        XCTAssertEqual(observation.current, true, "the seed populates the value when no change has arrived")
    }

    func testBundleDeliveredValueSurvivesLaterSeed() {
        let observation = FlagBundleObservation(keys: ["flag"], initial: [:])
        observation.testOnlyMerge(key: "flag", value: .bool(true))
        observation.testOnlySeed(key: "flag", value: .bool(false))
        XCTAssertEqual(observation.current["flag"], .bool(true), "a delivered key wins over a later seed")
    }

    func testBundleSeedAppliesWhenNothingDelivered() {
        let observation = FlagBundleObservation(keys: ["flag"], initial: [:])
        observation.testOnlySeed(key: "flag", value: .bool(true))
        XCTAssertEqual(observation.current["flag"], .bool(true), "the seed populates a key with no delivered change")
    }
}
