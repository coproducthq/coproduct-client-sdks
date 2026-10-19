import XCTest
@testable import Coproduct

final class CoproductActionTests: XCTestCase {
    func testNonActionURLReturnsNil() {
        XCTAssertNil(parseCoproductAction("https://example.com"))
    }

    func testRequestPermission() {
        let action = parseCoproductAction("coproduct-action:requestPermission?permission=camera")
        guard case let .requestPermission(permission) = action else { return XCTFail("wrong case") }
        XCTAssertEqual(permission, "camera")
    }

    func testOpenUrl() {
        let action = parseCoproductAction("coproduct-action:openUrl?url=https%3A%2F%2Fexample.com")
        guard case let .openUrl(url) = action else { return XCTFail("wrong case") }
        XCTAssertEqual(url, "https://example.com")
    }

    func testDismissAndComplete() {
        XCTAssertEqual(parseCoproductAction("coproduct-action:dismiss"), .dismiss)
        XCTAssertEqual(parseCoproductAction("coproduct-action:complete"), .complete)
    }

    func testShowPaywall() {
        let action = parseCoproductAction("coproduct-action:showPaywall?paywallId=pw_1")
        guard case let .showPaywall(paywallId) = action else { return XCTFail("wrong case") }
        XCTAssertEqual(paywallId, "pw_1")
    }

    func testRequestCollectsParamPrefixedParams() {
        let action = parseCoproductAction(
            "coproduct-action:request?operation=fetchUser&requestId=r1&param_userId=u1&param_scope=read"
        )
        guard case let .request(operation, requestId, params) = action else { return XCTFail("wrong case") }
        XCTAssertEqual(operation, "fetchUser")
        XCTAssertEqual(requestId, "r1")
        XCTAssertEqual(params, ["userId": "u1", "scope": "read"])
    }

    func testTrackDecodesJSONEncodedAnswers() {
        let encodedAnswers = "%7B%22q1%22%3A%5B%22yes%22%5D%7D" // {"q1":["yes"]}
        let action = parseCoproductAction(
            "coproduct-action:track?event=screen_viewed&screenId=s1&answers=\(encodedAnswers)"
        )
        guard case let .track(event, screenId, answers) = action else { return XCTFail("wrong case") }
        XCTAssertEqual(event, "screen_viewed")
        XCTAssertEqual(screenId, "s1")
        XCTAssertEqual(answers, ["q1": ["yes"]])
    }

    func testTrackWithoutAnswersDefaultsToEmpty() {
        let action = parseCoproductAction("coproduct-action:track?event=flow_dismissed&screenId=s1")
        guard case let .track(_, _, answers) = action else { return XCTFail("wrong case") }
        XCTAssertEqual(answers, [:])
    }

    func testUnknownActionReturnsNil() {
        XCTAssertNil(parseCoproductAction("coproduct-action:bogus"))
    }
}
