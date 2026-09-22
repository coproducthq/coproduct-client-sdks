import UIKit
import XCTest

@testable import coproduct

final class DeviceClassifierTests: XCTestCase {
    func testPhoneIdiom() {
        XCTAssertEqual(DeviceClassifier.deviceType(for: .phone), "phone")
    }

    func testPadIdiom() {
        XCTAssertEqual(DeviceClassifier.deviceType(for: .pad), "tablet")
    }

    func testTelevisionIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .tv))
    }

    func testCarPlayIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .carPlay))
    }

    func testMacIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .mac))
    }

    func testUnspecifiedIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .unspecified))
    }
}
