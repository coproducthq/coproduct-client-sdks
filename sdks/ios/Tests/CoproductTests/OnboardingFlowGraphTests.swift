import XCTest
@testable import Coproduct

final class OnboardingFlowGraphTests: XCTestCase {
    func testNextTargetDecodesScreen() throws {
        let json = Data(#"{"type":"screen","screenId":"s2"}"#.utf8)
        let target = try JSONDecoder().decode(NextTarget.self, from: json)
        XCTAssertEqual(target, .screen(screenId: "s2"))
    }

    func testNextTargetDecodesDismissAndComplete() throws {
        let dismiss = try JSONDecoder().decode(NextTarget.self, from: Data(#"{"type":"dismiss"}"#.utf8))
        XCTAssertEqual(dismiss, .dismiss)
        let complete = try JSONDecoder().decode(NextTarget.self, from: Data(#"{"type":"complete"}"#.utf8))
        XCTAssertEqual(complete, .complete)
    }

    func testNextTargetUnknownTypeThrows() {
        let json = Data(#"{"type":"bogus"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(NextTarget.self, from: json))
    }

    func testNextTargetRoundTripsThroughEncoding() throws {
        let original = NextTarget.screen(screenId: "s9")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NextTarget.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJSONValueDecodesEveryVariant() throws {
        let json = Data(#"{"a":null,"b":true,"c":1.5,"d":"s","e":[1,"x"],"f":{"g":1}}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case let .object(object) = value else { return XCTFail("expected object") }
        XCTAssertEqual(object["a"], .null)
        XCTAssertEqual(object["b"], .bool(true))
        XCTAssertEqual(object["c"], .number(1.5))
        XCTAssertEqual(object["d"], .string("s"))
        XCTAssertEqual(object["e"], .array([.number(1), .string("x")]))
        XCTAssertEqual(object["f"], .object(["g": .number(1)]))
    }

    func testScreenDecodesWithTransitionsAndOptionalOnLoad() throws {
        let json = Data(
            """
            {
              "id": "s1",
              "html": "<p>hi</p>",
              "transitions": [
                {"condition": {"op": "always"}, "next": {"type": "screen", "screenId": "s2"}}
              ],
              "defaultNext": {"type": "complete"}
            }
            """.utf8
        )
        let screen = try JSONDecoder().decode(Screen.self, from: json)
        XCTAssertEqual(screen.id, "s1")
        XCTAssertEqual(screen.transitions.count, 1)
        XCTAssertEqual(screen.transitions[0].next, .screen(screenId: "s2"))
        XCTAssertEqual(screen.defaultNext, .complete)
        XCTAssertNil(screen.onLoad)
    }

    func testScreenDecodesOnLoadWhenPresent() throws {
        let json = Data(
            """
            {
              "id": "s1", "html": "", "transitions": [], "defaultNext": {"type": "complete"},
              "onLoad": {"operation": "fetchUser", "params": {"k": "v"}, "resultKey": "user", "timeoutMs": 5000}
            }
            """.utf8
        )
        let screen = try JSONDecoder().decode(Screen.self, from: json)
        XCTAssertEqual(screen.onLoad, NativeOnLoadRequest(operation: "fetchUser", params: ["k": "v"], resultKey: "user", timeoutMs: 5000))
    }

    func testOnboardingFlowGraphDecodesAndLooksUpScreens() throws {
        let json = Data(
            """
            {
              "startScreenId": "s1",
              "screens": [
                {"id": "s1", "html": "", "transitions": [], "defaultNext": {"type": "complete"}}
              ]
            }
            """.utf8
        )
        let graph = try JSONDecoder().decode(OnboardingFlowGraph.self, from: json)
        XCTAssertEqual(graph.startScreenId, "s1")
        XCTAssertEqual(graph.screenById("s1")?.id, "s1")
        XCTAssertNil(graph.screenById("missing"))
    }
}
