import XCTest
@testable import Coproduct

final class PaywallActionTests: XCTestCase {
    func testNonActionURLReturnsNil() {
        XCTAssertNil(parsePaywallAction("https://example.com"))
    }

    func testPurchaseWithPackageKey() {
        let action = parsePaywallAction("coproduct-action:purchase?packageKey=monthly")
        guard case let .purchase(packageKey) = action else { return XCTFail("wrong case") }
        XCTAssertEqual(packageKey, "monthly")
    }

    func testPurchaseWithoutPackageKeyReturnsNil() {
        XCTAssertNil(parsePaywallAction("coproduct-action:purchase"))
    }

    func testPurchaseWithEmptyPackageKeyReturnsNil() {
        XCTAssertNil(parsePaywallAction("coproduct-action:purchase?packageKey="))
    }

    func testRestoreAndDismiss() {
        XCTAssertEqual(parsePaywallAction("coproduct-action:restore"), .restore)
        XCTAssertEqual(parsePaywallAction("coproduct-action:dismiss"), .dismiss)
    }

    func testUnknownActionReturnsNil() {
        XCTAssertNil(parsePaywallAction("coproduct-action:bogus"))
    }
}
