import XCTest
@testable import Coproduct

final class AccountTokenTests: XCTestCase {
    func testAccountTokenMatchesTheServerVector() {
        // The server recomputes this value from the app user id, so the
        // vector is shared with the platform and the other SDKs.
        XCTAssertEqual(
            accountToken(forAppUserId: "user-123").uuidString.lowercased(),
            "f5765ad4-640f-516d-be70-79ed3a75f5e7"
        )
    }

    func testAccountTokenIsStableAndDistinctPerAppUserId() {
        XCTAssertEqual(accountToken(forAppUserId: "user-123"), accountToken(forAppUserId: "user-123"))
        XCTAssertNotEqual(accountToken(forAppUserId: "user-123"), accountToken(forAppUserId: "user-124"))
    }
}
