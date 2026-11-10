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

    // MARK: - formattedOfferPeriod

    func testFormattedOfferPeriodSinglePeriodIsSingular() {
        XCTAssertEqual(formattedOfferPeriod(unit: .month, value: 1, periodCount: 1), "1 month")
    }

    func testFormattedOfferPeriodMultipliesPeriodCountIntoTotalDuration() {
        // A pay-as-you-go "$1.99/month for 3 months" offer reports
        // offer.period = 1 month and offer.periodCount = 3 -- the rendered
        // phrase must reflect the TOTAL duration, "3 months", not "1 month".
        XCTAssertEqual(formattedOfferPeriod(unit: .month, value: 1, periodCount: 3), "3 months")
    }

    func testFormattedOfferPeriodMultipliesMultiUnitValueByPeriodCount() {
        // A 2-week base period repeated 3 times totals 6 weeks.
        XCTAssertEqual(formattedOfferPeriod(unit: .week, value: 2, periodCount: 3), "6 weeks")
    }

    func testFormattedOfferPeriodYearSingular() {
        XCTAssertEqual(formattedOfferPeriod(unit: .year, value: 1, periodCount: 1), "1 year")
    }

    func testFormattedOfferPeriodDayPlural() {
        XCTAssertEqual(formattedOfferPeriod(unit: .day, value: 7, periodCount: 1), "7 days")
    }

    // MARK: - appendingRenewalSuffix

    func testAppendingRenewalSuffixMonth() {
        XCTAssertEqual(appendingRenewalSuffix(to: "$9.99", unit: .month), "$9.99/mo")
    }

    func testAppendingRenewalSuffixYear() {
        XCTAssertEqual(appendingRenewalSuffix(to: "$39.99", unit: .year), "$39.99/yr")
    }

    func testAppendingRenewalSuffixWeek() {
        XCTAssertEqual(appendingRenewalSuffix(to: "$2.99", unit: .week), "$2.99/wk")
    }

    func testAppendingRenewalSuffixDay() {
        XCTAssertEqual(appendingRenewalSuffix(to: "$0.99", unit: .day), "$0.99/day")
    }

    // MARK: - composeIntroLabel with realistic multi-period / suffixed values

    func testPayAsYouGoLabelWithMultiPeriodOfferAndSuffixedRegularPrice() {
        // "$1.99/month for 3 months, then $39.99/yr" -- a realistic
        // pay-as-you-go offer whose total duration spans several of its base
        // periods, renewing into an annual plan.
        let offerPeriod = formattedOfferPeriod(unit: .month, value: 1, periodCount: 3)
        let regularPrice = appendingRenewalSuffix(to: "$39.99", unit: .year)
        let label = composeIntroLabel(kind: .payAsYouGo, offerPeriod: offerPeriod, offerPrice: "$1.99", regularPrice: regularPrice)
        XCTAssertEqual(label, "$1.99 for 3 months, then $39.99/yr")
    }

    func testFreeTrialLabelWithSuffixedRegularPrice() {
        let regularPrice = appendingRenewalSuffix(to: "$39.99", unit: .year)
        let label = composeIntroLabel(kind: .freeTrial, offerPeriod: formattedOfferPeriod(unit: .day, value: 7, periodCount: 1), offerPrice: "", regularPrice: regularPrice)
        XCTAssertEqual(label, "7 days free, then $39.99/yr")
    }
}
