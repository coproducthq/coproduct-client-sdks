import XCTest
@testable import Coproduct

final class DeviceContextTests: XCTestCase {
    func testStaticAttributesCarryTheSdkOwnedFacts() {
        let attrs = DeviceContext.staticAttributes()

        XCTAssertEqual(attrs["platform"], .string("ios"))

        // os_version is formatted from the struct components, three numeric parts
        guard case let .string(osVersion)? = attrs["os_version"] else {
            return XCTFail("os_version must be a string")
        }
        let parts = osVersion.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "os_version is major.minor.patch, got \(osVersion)")
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil })

        // timezone is the canonical IANA identifier, which always contains a
        // slash or is UTC, never an abbreviation like PST
        guard case let .string(timezone)? = attrs["timezone"] else {
            return XCTFail("timezone must be a string")
        }
        XCTAssertEqual(timezone, TimeZone.current.identifier)

        // locale is the raw preferred language. The core owns hyphenation, so
        // the wrapper only guarantees presence when the platform reports one
        if case let .string(locale)? = attrs["locale"] {
            XCTAssertFalse(locale.isEmpty)
        }

        // device_type in the test runner is a mapped idiom or absent, never a sentinel
        if case let .string(deviceType)? = attrs["device_type"] {
            XCTAssertTrue(["phone", "tablet"].contains(deviceType))
        }

        // The collector never emits keys outside the SDK-owned static set
        let allowed: Set<String> = [
            "platform", "os_version", "app_version", "app_build",
            "locale", "timezone", "device_type",
        ]
        XCTAssertTrue(Set(attrs.keys).isSubset(of: allowed))
    }

    func testDeviceTypeMappingIsPhoneTabletOrNil() {
        #if canImport(UIKit)
        XCTAssertEqual(DeviceContext.deviceType(for: .phone), "phone")
        XCTAssertEqual(DeviceContext.deviceType(for: .pad), "tablet")
        XCTAssertNil(DeviceContext.deviceType(for: .tv))
        XCTAssertNil(DeviceContext.deviceType(for: .carPlay))
        XCTAssertNil(DeviceContext.deviceType(for: .unspecified))
        #endif
    }
}
