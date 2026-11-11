import XCTest
@testable import Coproduct

final class PaywallPackageRuntimeTests: XCTestCase {
    private func encode(_ value: [String: PaywallPackageRuntime]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try encoder.encode(value), encoding: .utf8)!
    }

    func testEncodesEligibleIntroToBridgeShape() throws {
        let json = try encode(["annual": PaywallPackageRuntime(price: "$39.99", intro: PaywallIntroOffer(eligible: true, label: "7 days free, then $39.99/yr"))])
        XCTAssertEqual(json, "{\"annual\":{\"intro\":{\"eligible\":true,\"label\":\"7 days free, then $39.99/yr\"},\"price\":\"$39.99\"}}")
    }

    func testEncodesNoOfferAsNullIntro() throws {
        let json = try encode(["monthly": PaywallPackageRuntime(price: "$6.99", intro: nil)])
        XCTAssertEqual(json, "{\"monthly\":{\"intro\":null,\"price\":\"$6.99\"}}")
    }
}
