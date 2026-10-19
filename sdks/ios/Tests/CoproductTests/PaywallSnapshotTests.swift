import XCTest
@testable import Coproduct

final class PaywallSnapshotTests: XCTestCase {
    func testPackageKindDefaultsToSubscriptionWhenAbsent() throws {
        let json = Data(#"{"iosProductId":"p1"}"#.utf8)
        let ref = try JSONDecoder().decode(PaywallPackageRef.self, from: json)
        XCTAssertEqual(ref.kind, .subscription)
    }

    func testPackageKindDecodesConsumableAndLifetime() throws {
        let consumable = try JSONDecoder().decode(PaywallPackageRef.self, from: Data(#"{"kind":"consumable"}"#.utf8))
        XCTAssertEqual(consumable.kind, .consumable)
        let lifetime = try JSONDecoder().decode(PaywallPackageRef.self, from: Data(#"{"kind":"lifetime"}"#.utf8))
        XCTAssertEqual(lifetime.kind, .lifetime)
    }

    func testPackageKindDefaultsToSubscriptionForUnrecognizedValue() throws {
        let ref = try JSONDecoder().decode(PaywallPackageRef.self, from: Data(#"{"kind":"future_kind"}"#.utf8))
        XCTAssertEqual(ref.kind, .subscription)
    }

    func testPaywallPackageRefEveryProductIdIsOptional() throws {
        let ref = try JSONDecoder().decode(PaywallPackageRef.self, from: Data("{}".utf8))
        XCTAssertNil(ref.iosProductId)
        XCTAssertNil(ref.androidProductId)
        XCTAssertNil(ref.webProductId)
    }

    func testPaywallSnapshotDecodesFullShape() throws {
        let json = Data(
            """
            {
              "paywallId": "pw_1", "version": 3, "templateType": "default",
              "content": {"offeringKey": "off_1", "ctas": [{"packageKey": "monthly", "label": "Monthly"}], "html": "<p>a</p>"},
              "packages": {"monthly": {"iosProductId": "com.app.monthly", "kind": "subscription"}},
              "html": "<p>full</p>"
            }
            """.utf8
        )
        let snapshot = try JSONDecoder().decode(PaywallSnapshot.self, from: json)
        XCTAssertEqual(snapshot.paywallId, "pw_1")
        XCTAssertEqual(snapshot.content.ctas.first?.packageKey, "monthly")
        XCTAssertEqual(snapshot.packages["monthly"]?.iosProductId, "com.app.monthly")
    }
}
