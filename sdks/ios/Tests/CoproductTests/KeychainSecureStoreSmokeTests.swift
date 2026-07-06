import XCTest
@testable import Coproduct

final class KeychainSecureStoreSmokeTests: XCTestCase {
    func testKeychainSecureStoreImplementsHostSecureStore() {
        let store: any HostSecureStore = KeychainSecureStore(service: "app.coproduct.sdk.test")
        XCTAssertNotNil(store)
    }
}
