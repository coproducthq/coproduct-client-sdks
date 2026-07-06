import XCTest
@testable import Coproduct

final class ConfigTests: XCTestCase {
    func testDefaultConfigCarriesSpecDefaults() {
        let config = CoproductConfig()
        XCTAssertEqual(config.pollInterval, 60)
        XCTAssertEqual(config.startupTimeout, 3)
        XCTAssertNil(config.anonymousId)
        XCTAssertNil(config.transport)
        XCTAssertNil(config.secureStore)
        XCTAssertNil(config.endpoint)
        XCTAssertEqual(config.pollOnForeground, true)
        XCTAssertNil(config.evaluationListener)
        // requestTimeout defaults to nil meaning the platform transport uses
        // its native default (URLSession 60s on iOS)
        XCTAssertNil(config.requestTimeout)
    }

    func testRequestTimeoutOverride() {
        let config = CoproductConfig(requestTimeout: 90)
        XCTAssertEqual(config.requestTimeout, 90)
    }

    func testExplicitFieldOverrides() {
        let config = CoproductConfig(
            pollInterval: 30,
            startupTimeout: 5,
            anonymousId: "my-device",
            endpoint: "https://edge.example.com",
            pollOnForeground: false
        )
        XCTAssertEqual(config.pollInterval, 30)
        XCTAssertEqual(config.startupTimeout, 5)
        XCTAssertEqual(config.anonymousId, "my-device")
        XCTAssertEqual(config.endpoint, "https://edge.example.com")
        XCTAssertEqual(config.pollOnForeground, false)
    }
}
