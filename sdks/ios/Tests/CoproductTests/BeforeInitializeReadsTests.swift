import XCTest
@testable import Coproduct

// Reads must not crash before initialize. Flag getters return the supplied
// default, detail getters return that default with provider-not-ready metadata,
// optional reads return nil, and the diagnostic snapshot reports its empty value
final class BeforeInitializeReadsTests: XCTestCase {
    private struct Box: Codable, Equatable {
        let n: Int
    }

    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testGettersReturnDefaultsBeforeInitialize() {
        XCTAssertEqual(Coproduct.state, .notReady)
        XCTAssertEqual(Coproduct.getBool("x", default: true), true)
        XCTAssertEqual(Coproduct.getString("x", default: "d"), "d")
        XCTAssertEqual(Coproduct.getInt("x", default: 7), 7)
        XCTAssertEqual(Coproduct.getNumber("x", default: 1.5), 1.5)
        XCTAssertEqual(Coproduct.getJSON("x", default: Box(n: 3)), Box(n: 3))
    }

    func testDetailsReturnDefaultWithNotReadyBeforeInitialize() {
        let boolDetails = Coproduct.getBoolDetails("x", default: true)
        guard case let .bool(boolValue) = boolDetails.value else {
            return XCTFail("expected a bool detail value, got \(boolDetails.value)")
        }
        XCTAssertTrue(boolValue)
        assertNotReady(boolDetails)

        let stringDetails = Coproduct.getStringDetails("x", default: "d")
        guard case let .string(stringValue) = stringDetails.value else {
            return XCTFail("expected a string detail value, got \(stringDetails.value)")
        }
        XCTAssertEqual(stringValue, "d")
        assertNotReady(stringDetails)

        let intDetails = Coproduct.getIntDetails("x", default: 7)
        guard case let .int(intValue) = intDetails.value else {
            return XCTFail("expected an int detail value, got \(intDetails.value)")
        }
        XCTAssertEqual(intValue, 7)
        assertNotReady(intDetails)

        let numberDetails = Coproduct.getNumberDetails("x", default: 1.5)
        guard case let .number(numberValue) = numberDetails.value else {
            return XCTFail("expected a number detail value, got \(numberDetails.value)")
        }
        XCTAssertEqual(numberValue, 1.5)
        assertNotReady(numberDetails)

        let jsonDetails = Coproduct.getJSONDetails("x", default: Box(n: 3))
        guard case let .json(jsonValue) = jsonDetails.value else {
            return XCTFail("expected a json detail value, got \(jsonDetails.value)")
        }
        XCTAssertEqual(try? JSONDecoder().decode(Box.self, from: Data(jsonValue.utf8)), Box(n: 3))
        assertNotReady(jsonDetails)
    }

    // Every pre-init detail carries provider-not-ready metadata for the flag key
    private func assertNotReady(_ details: FlagEvaluationDetails) {
        XCTAssertNil(details.variant)
        XCTAssertEqual(details.errorCode, "PROVIDER_NOT_READY")
        XCTAssertEqual(details.flagKey, "x")
    }

    func testPreviousAnonymousIdIsNilBeforeInitialize() {
        XCTAssertNil(Coproduct.previousAnonymousId)
    }

    func testSnapshotIsEmptyBeforeInitialize() {
        XCTAssertEqual(Coproduct.snapshot.version, 0)
        XCTAssertEqual(Coproduct.snapshot.flagCount, 0)
    }

    // The fire-and-forget identity calls log and no-op before initialize rather
    // than trapping. Reaching the end of this test without a crash is the proof,
    // and no instance is created as a side effect
    func testIdentityCallsBeforeInitializeDoNotTrap() {
        Coproduct.identify(userId: "alice")
        Coproduct.identify(userId: "bob", attributes: ["tier": .string("gold")], linkAnonymous: false)
        Coproduct.updateAttributes(["region": .string("eu")])
        Coproduct.removeAttributes(["region"])
        Coproduct.setContext(targetingKey: "team-42")
        Coproduct.signOut()

        XCTAssertNil(Instances.shared.defaultInstance(), "identity calls must not create an instance")
        XCTAssertEqual(Coproduct.state, .notReady)
    }
}
