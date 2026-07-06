import Combine
import SwiftUI
import XCTest
@testable import Coproduct

// @CoproductFlag SwiftUI integration coverage.
//
// The wrapper's storage ($-synthesized _x) is private to its owning view and the
// wrappedValue is read through @StateObject, which only materializes inside a
// real SwiftUI render pass. Rather than reach into that storage, these tests
// exercise the exact plumbing the wrapper delegates to: the CoproductFlagValue
// protocol that feeds the wrapper's published value, and the guarded
// subscription contract.
//
// The wrapper attaches its subscription once a default instance exists, gated on
// Instances.shared.defaultInstance() rather than provider state. Built before
// initialize it serves the supplied default and attaches when a default instance
// becomes available. After initialize with a test transport the observation
// publisher is live and emits the current value to a new subscriber. The wrapper
// itself is also constructed for every supported type to confirm the generic
// surface compiles and instantiates
@MainActor
final class PropertyWrapperTests: XCTestCase {
    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    // A ready notification can be delivered on the main queue after a shutdown has
    // already niled the default instance. A live holder receiving it must not trap
    // in requireDefault. Without the guard in subscribe() this crashes the runner
    func testReadyNotificationWithNoInstanceDoesNotTrap() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let holder = CoproductFlag<Bool>.Holder(key: "x", defaultValue: false)
        XCTAssertFalse(holder.isSubscribed)

        NotificationCenter.default.post(name: .coproductDefaultInstanceReady, object: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(holder.isSubscribed, "no instance exists, so it must not subscribe or trap")
        XCTAssertFalse(holder.value)
    }

    private func initializeWithTestTransport() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 1,
            transport: TestTransport(),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(
            sdkKey: "cpk_mob_" + String(repeating: "w", count: 32),
            config: config
        )
    }

    // Subscribe to the value publisher the wrapper uses and collect the synchronous
    // emissions a fresh subscriber receives
    private func firstEmissions<Value: CoproductFlagValue>(
        of type: Value.Type,
        key: String,
        default defaultValue: Value
    ) -> [Value] {
        var received: [Value] = []
        let cancellable = Value.observe(key: key, defaultValue: defaultValue)
            .sink { received.append($0) }
        cancellable.cancel()
        return received
    }

    func testWrapperStaysInertBeforeInitialize() async throws {
        // No initialize has run, so no default instance exists. The Holder must
        // not subscribe (which would trap in requireDefault) until one does, so
        // constructing the wrapper without a crash is the observable proof
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        XCTAssertEqual(Coproduct.state, .notReady)

        let flag = CoproductFlag("missing-flag", default: true)
        _ = flag
        // Reaching here means the wrapper did not subscribe before a default instance existed
        XCTAssertEqual(Coproduct.state, .notReady)
    }

    func testObservationServesDefaultForUnknownFlagAfterInitialize() async throws {
        try await initializeWithTestTransport()

        // The test transport returns an empty snapshot, so an unknown flag still
        // resolves to the supplied default even though the SDK is ready
        let emissions = firstEmissions(of: Int.self, key: "missing-flag", default: 7)
        XCTAssertEqual(emissions.first, 7)
    }

    func testProjectedPublisherEmitsCurrentValueAfterInitialize() async throws {
        try await initializeWithTestTransport()

        // A fresh subscriber to the wrapper's underlying publisher sees the
        // current value immediately, which is what feeds the @Published projection
        var received: [Int] = []
        let cancellable = Int.observe(key: "missing-flag", defaultValue: 1)
            .sink { received.append($0) }
        defer { cancellable.cancel() }
        XCTAssertGreaterThanOrEqual(received.count, 1)
        XCTAssertEqual(received.first, 1)
    }

    func testWrapperBacksAllSupportedTypes() async throws {
        try await initializeWithTestTransport()

        // Construct the wrapper for every CoproductFlagValue conformance to
        // confirm the generic surface compiles and instantiates for each type
        _ = CoproductFlag("b", default: false)
        _ = CoproductFlag("s", default: "hi")
        _ = CoproductFlag("i", default: 3)
        _ = CoproductFlag("n", default: 1.5)

        XCTAssertEqual(firstEmissions(of: Bool.self, key: "b", default: false), [false])
        XCTAssertEqual(firstEmissions(of: String.self, key: "s", default: "hi"), ["hi"])
        XCTAssertEqual(firstEmissions(of: Int.self, key: "i", default: 3), [3])
        XCTAssertEqual(firstEmissions(of: Double.self, key: "n", default: 1.5), [1.5])
    }

    func testHolderAttachesAfterLateInitialize() async throws {
        // The README pattern builds the view (and its @CoproductFlag) before the
        // .task that calls initialize. Construct the holder before initialize and
        // confirm it attaches once the SDK becomes ready rather than staying
        // permanently inert
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        XCTAssertEqual(Coproduct.state, .notReady)

        let holder = CoproductFlag<Bool>.Holder(key: "missing-flag", defaultValue: false)
        XCTAssertFalse(holder.isSubscribed)

        try await initializeWithTestTransport()
        // The ready signal is delivered on the main queue, so let it drain
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(holder.isSubscribed)
    }

    func testHolderReattachesAcrossShutdownAndReinitialize() async throws {
        // A retained SwiftUI view must keep working across shutdown then a new
        // initialize. The holder detaches on shutdown and re-attaches to the new
        // default instance, rather than going permanently stale
        try await initializeWithTestTransport()
        let holder = CoproductFlag<Bool>.Holder(key: "missing-flag", defaultValue: false)
        XCTAssertTrue(holder.isSubscribed)

        await Coproduct.shutdown()

        clearCoproductSnapshotCache()
        // The shutdown signal is delivered on the main queue, so let it drain
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(holder.isSubscribed)

        try await initializeWithTestTransport()
        // The ready signal is delivered on the main queue, so let it drain
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(holder.isSubscribed)
    }
}
