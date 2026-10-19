import XCTest
@testable import Coproduct

final class EntitlementTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testDecodesActiveSubscriptionEntitlement() throws {
        let json = Data(
            """
            {"entitlementId": "ent_1", "isActive": true, "expiresAt": "2026-12-01T00:00:00Z", "willRenew": true, "source": "app_store"}
            """.utf8
        )
        let entitlement = try decoder().decode(Entitlement.self, from: json)
        XCTAssertEqual(entitlement.entitlementId, "ent_1")
        XCTAssertTrue(entitlement.isActive)
        XCTAssertNotNil(entitlement.expiresAt)
        XCTAssertTrue(entitlement.willRenew)
        XCTAssertEqual(entitlement.source, "app_store")
    }

    func testExpiresAtIsNilForLifetimeEntitlement() throws {
        let json = Data(
            #"{"entitlementId": "ent_2", "isActive": true, "willRenew": false, "source": "app_store"}"#.utf8
        )
        let entitlement = try decoder().decode(Entitlement.self, from: json)
        XCTAssertNil(entitlement.expiresAt)
    }
}
