import XCTest
@testable import Coproduct

// initialize funnels every launch failure through CoproductError, so a caller
// catches one Swift error type and never a generated FFI error. These assert the
// error type and case for the failure modes a developer can trigger: a wrapper
// numeric guard, a core config range check, and malformed or missing sdk keys.
final class InitializeErrorContractTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    // Caught the raw generated type instead of CoproductError. Kept separate so a
    // failure names the leaking type rather than a generic mismatch
    private func failGeneric(_ error: Error) {
        XCTFail("expected CoproductError, got \(type(of: error)): \(error)")
    }

    // A value the wrapper rejects before the FFI call (negative seconds cannot be
    // represented). The wrapper itself throws, and it is already a CoproductError
    func testNegativeConfigValueThrowsInvalidConfig() async {
        do {
            try await Coproduct.initialize(
                sdkKey: Self.validKey,
                config: CoproductConfig(pollInterval: -5, secureStore: TestSecureStore())
            )
            XCTFail("expected initialize to throw")
        } catch let error as CoproductError {
            guard case let .invalidConfig(field, _) = error else {
                return XCTFail("expected .invalidConfig, got \(error)")
            }
            XCTAssertEqual(field, "pollInterval")
        } catch {
            failGeneric(error)
        }
    }

    // A value the wrapper accepts but the Rust core rejects (below the minimum
    // poll interval). The core throws InitError, which must surface as a mapped
    // CoproductError rather than the raw generated type
    func testConfigBelowCoreMinimumThrowsInvalidConfig() async {
        do {
            try await Coproduct.initialize(
                sdkKey: Self.validKey,
                config: CoproductConfig(pollInterval: 10, secureStore: TestSecureStore())
            )
            XCTFail("expected initialize to throw")
        } catch let error as CoproductError {
            guard case .invalidConfig = error else {
                return XCTFail("expected .invalidConfig, got \(error)")
            }
        } catch {
            failGeneric(error)
        }
    }

    func testMalformedSdkKeyThrowsInvalidSdkKey() async {
        do {
            try await Coproduct.initialize(
                sdkKey: "cpk_mob_tooshort",
                config: CoproductConfig(secureStore: TestSecureStore())
            )
            XCTFail("expected initialize to throw")
        } catch let error as CoproductError {
            guard case .invalidSdkKey = error else {
                return XCTFail("expected .invalidSdkKey, got \(error)")
            }
        } catch {
            failGeneric(error)
        }
    }

    func testEmptySdkKeyThrowsInvalidSdkKey() async {
        do {
            try await Coproduct.initialize(
                sdkKey: "",
                config: CoproductConfig(secureStore: TestSecureStore())
            )
            XCTFail("expected initialize to throw")
        } catch let error as CoproductError {
            guard case .invalidSdkKey = error else {
                return XCTFail("expected .invalidSdkKey, got \(error)")
            }
        } catch {
            failGeneric(error)
        }
    }
}
