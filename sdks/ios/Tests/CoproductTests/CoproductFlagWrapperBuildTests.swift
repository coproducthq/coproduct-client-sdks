import XCTest
import SwiftUI
@testable import Coproduct

final class CoproductFlagWrapperBuildTests: XCTestCase {
    func testWrapperCompilesAsViewProperty() {
        struct UnderTest: View {
            @CoproductFlag("new-checkout", default: false) var newCheckout: Bool
            @CoproductFlag("welcome-msg", default: "Hi") var welcome: String
            var body: some View {
                Text(welcome) + Text(newCheckout ? "on" : "off")
            }
        }
        _ = UnderTest()
        XCTAssertTrue(true)
    }
}
