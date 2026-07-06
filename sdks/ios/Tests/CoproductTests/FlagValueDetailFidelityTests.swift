import XCTest
@testable import Coproduct

// FlagValue.detailValue backs both bundle observation and the evaluation hook
// context. It must keep each flag's type, in particular integer precision beyond
// what a double can hold and JSON kept distinct from a plain string
final class FlagValueDetailFidelityTests: XCTestCase {
    func testDetailValuePreservesEachType() {
        XCTAssertEqual(FlagValue.bool(value: true).detailValue, .bool(true))
        XCTAssertEqual(FlagValue.string(value: "s").detailValue, .string("s"))
        XCTAssertEqual(FlagValue.number(value: 1.5).detailValue, .number(1.5))
        XCTAssertEqual(FlagValue.json(value: "{\"a\":1}").detailValue, .json("{\"a\":1}"))
    }

    func testDetailValueKeepsLargeIntegerPrecision() {
        // 2^53 + 1 is the first integer a double cannot represent exactly, so a
        // detour through Double would corrupt it
        let big: Int64 = 9_007_199_254_740_993
        guard case let .int(value) = FlagValue.int(value: big).detailValue else {
            return XCTFail("expected an int detail value")
        }
        XCTAssertEqual(value, big)
    }

    func testJSONStaysDistinctFromString() {
        // A JSON string payload must stay .json rather than collapsing to .string
        guard case .json = FlagValue.json(value: "\"hello\"").detailValue else {
            return XCTFail("expected a json detail value")
        }
    }
}
