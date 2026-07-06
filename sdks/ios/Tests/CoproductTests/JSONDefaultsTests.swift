import Foundation
import XCTest
@testable import Coproduct

// getJSON and getJSONDetails must honor the caller-supplied default for an
// absent flag. The plain getter decodes the default back from the wire default,
// and the details getter must report the default rather than a JSON null
final class JSONDefaultsTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    private struct Box: Codable, Equatable {
        let n: Int
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    private func initializeWithTestTransport() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 1,
            transport: TestTransport(),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)
    }

    func testGetJSONReturnsProvidedDefaultForAbsentFlag() async throws {
        try await initializeWithTestTransport()
        let value = Coproduct.getJSON("missing-flag", default: Box(n: 7))
        XCTAssertEqual(value, Box(n: 7))
    }

    func testGetJSONDetailsReportsProvidedDefaultNotNull() async throws {
        try await initializeWithTestTransport()
        let details = Coproduct.getJSONDetails("missing-flag", default: Box(n: 42))
        guard case let .json(raw) = details.value else {
            return XCTFail("expected a json detail value, got \(details.value)")
        }
        XCTAssertNotEqual(raw, "null")
        let decoded = try JSONDecoder().decode(Box.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded, Box(n: 42))
    }
}
