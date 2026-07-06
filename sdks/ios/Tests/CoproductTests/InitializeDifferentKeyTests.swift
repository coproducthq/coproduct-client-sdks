import XCTest
@testable import Coproduct

// Re-initializing an already-live instance returns the existing client even
// when the caller passes a different sdk key. The second key is ignored and a
// warning is logged. The registry stores the key Swift-side and never exports
// it back over FFI, so the observable contract under test is instance identity
// rather than the logged message
final class InitializeDifferentKeyTests: XCTestCase {
    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    private func validKey(body letter: Character) -> String {
        "cpk_mob_" + String(repeating: letter, count: 32)
    }

    private func mockConfig() -> CoproductConfig {
        CoproductConfig(
            pollInterval: 60,
            startupTimeout: 1,
            transport: TestTransport(),
            secureStore: TestSecureStore()
        )
    }

    // initialize returns Void, so identity is observed through the internal
    // registry: the stored instance must be the same object after a re-init
    func testSecondInitWithDifferentKeyReturnsExisting() async throws {
        try await Coproduct.initialize(sdkKey: validKey(body: "a"), config: mockConfig())
        let first = try XCTUnwrap(Instances.shared.defaultInstance())
        try await Coproduct.initialize(sdkKey: validKey(body: "b"), config: mockConfig())
        let second = try XCTUnwrap(Instances.shared.defaultInstance())
        XCTAssertTrue(first === second)
    }

    func testSecondInitWithSameKeyReturnsExisting() async throws {
        let key = validKey(body: "c")
        try await Coproduct.initialize(sdkKey: key, config: mockConfig())
        let first = try XCTUnwrap(Instances.shared.defaultInstance())
        try await Coproduct.initialize(sdkKey: key, config: mockConfig())
        let second = try XCTUnwrap(Instances.shared.defaultInstance())
        XCTAssertTrue(first === second)
    }

}
