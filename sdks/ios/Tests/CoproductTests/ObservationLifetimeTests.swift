import Combine
import XCTest
@testable import Coproduct

// A subscriber to a FlagObservation's publisher must keep the observation, and
// so its underlying core subscription, alive. Otherwise the observation deinits
// as soon as the caller keeps only the publisher and later changes never arrive
@MainActor
final class ObservationLifetimeTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        try await Coproduct.initialize(
            sdkKey: Self.validKey,
            config: CoproductConfig(
                startupTimeout: 1,
                transport: TestTransport(),
                secureStore: TestSecureStore()
            )
        )
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testPublisherKeepsObservationAliveWhileSubscribed() {
        weak var weakObservation: FlagObservation<Bool>?
        var cancellable: AnyCancellable?
        do {
            let observation = Coproduct.observe("missing-flag", default: false)
            weakObservation = observation
            cancellable = observation.publisher.sink { _ in }
            // The strong reference goes out of scope here; only the publisher
            // subscription should keep the observation alive
        }
        XCTAssertNotNil(weakObservation, "an active subscriber must keep the observation alive")

        cancellable?.cancel()
        cancellable = nil
        XCTAssertNil(weakObservation, "the observation should be released once nothing subscribes")
    }
}
