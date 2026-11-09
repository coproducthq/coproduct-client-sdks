import XCTest
@testable import Coproduct

final class IntroOfferLabelTests: XCTestCase {
    func testFreeTrialLabel() {
        let label = composeIntroLabel(kind: .freeTrial, offerPeriod: "7 days", offerPrice: "", regularPrice: "$39.99/yr")
        XCTAssertEqual(label, "7 days free, then $39.99/yr")
    }

    func testPayUpFrontLabel() {
        let label = composeIntroLabel(kind: .payUpFront, offerPeriod: "3 months", offerPrice: "$0.99", regularPrice: "$9.99/mo")
        XCTAssertEqual(label, "$0.99 for 3 months, then $9.99/mo")
    }

    func testPayAsYouGoLabel() {
        let label = composeIntroLabel(kind: .payAsYouGo, offerPeriod: "2 months", offerPrice: "$1.99", regularPrice: "$9.99/mo")
        XCTAssertEqual(label, "$1.99 for 2 months, then $9.99/mo")
    }
}
