import XCTest
@testable import Coproduct

final class PermissionBridgeTests: XCTestCase {
    override func tearDown() {
        PermissionBridge.requestPermissionOverrideForTesting = nil
        super.tearDown()
    }

    func testUnknownPermissionNameReturnsErrorStatusWithoutThrowing() async throws {
        let result = try await PermissionBridge.requestPermission("bogus")
        XCTAssertEqual(result["status"], "error")
        XCTAssertEqual(result["message"], "Unknown permission \"bogus\"")
    }

    func testOverrideForTestingIsUsedWhenSet() async throws {
        PermissionBridge.requestPermissionOverrideForTesting = { permission in
            ["status": "granted", "echoedPermission": permission]
        }
        let result = try await PermissionBridge.requestPermission("camera")
        XCTAssertEqual(result["status"], "granted")
        XCTAssertEqual(result["echoedPermission"], "camera")
    }

    func testOverrideCanThrow() async {
        struct TestError: Error {}
        PermissionBridge.requestPermissionOverrideForTesting = { _ in throw TestError() }
        do {
            _ = try await PermissionBridge.requestPermission("camera")
            XCTFail("expected throw")
        } catch is TestError {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
