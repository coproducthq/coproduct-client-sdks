import XCTest
@testable import Coproduct

final class UtmStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "app.coproduct.tests.utmstore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFirstTouchIsFrozenAcrossCaptures() {
        let store = UtmStore(defaults: defaults)

        let first = store.capture(url: "https://x.com/?utm_source=google")
        XCTAssertEqual(first["utm_source"], .string("google"))

        let second = store.capture(url: "https://x.com/?utm_source=facebook")
        XCTAssertEqual(second["utm_source"], .string("google"))

        // A fresh store instance over the same defaults reads the same frozen
        // value, so the freeze is persisted rather than held in memory
        XCTAssertEqual(
            UtmStore(defaults: defaults).utmAttributes()["utm_source"],
            .string("google")
        )
    }

    func testLastTouchOverwritesOnEveryCapture() {
        let store = UtmStore(defaults: defaults)

        let first = store.capture(url: "https://x.com/?utm_source=google")
        XCTAssertEqual(first["utm_source_last"], .string("google"))

        let second = store.capture(url: "https://x.com/?utm_source=facebook")
        XCTAssertEqual(second["utm_source_last"], .string("facebook"))

        // First-touch stays frozen while last-touch moved, confirming the two
        // attributes track independently from a single capture call
        XCTAssertEqual(second["utm_source"], .string("google"))
    }

    func testEmptyValuesAreOmittedFromTheFlattenedSet() {
        let store = UtmStore(defaults: defaults)
        let attributes = store.capture(url: "https://x.com/?utm_source=&utm_campaign=bf")

        XCTAssertNil(attributes["utm_source"])
        XCTAssertNil(attributes["utm_source_last"])
        XCTAssertEqual(attributes["utm_campaign"], .string("bf"))
        XCTAssertEqual(attributes["utm_campaign_last"], .string("bf"))
    }

    func testUtmAttributesReadsPersistedSetWithoutCapturing() {
        let store = UtmStore(defaults: defaults)
        _ = store.capture(url: "https://x.com/?utm_source=google&utm_campaign=bf")

        // A read-only store reads the same values back without needing a URL
        let readOnly = UtmStore(defaults: defaults)
        let attributes = readOnly.utmAttributes()
        XCTAssertEqual(attributes["utm_source"], .string("google"))
        XCTAssertEqual(attributes["utm_source_last"], .string("google"))
        XCTAssertEqual(attributes["utm_campaign"], .string("bf"))
        XCTAssertEqual(attributes["utm_campaign_last"], .string("bf"))
    }

    func testCaptureWithNoUtmParametersPersistsNothingAndReturnsStoredSet() {
        let store = UtmStore(defaults: defaults)
        _ = store.capture(url: "https://x.com/?utm_source=google")

        let unrelated = store.capture(url: "https://x.com/path?foo=bar")
        XCTAssertEqual(unrelated["utm_source"], .string("google"))
        XCTAssertEqual(unrelated["utm_source_last"], .string("google"))
        XCTAssertNil(unrelated["utm_campaign"])
    }

    // Exercises the real parseUtmParameters FFI call, confirming the UniFFI
    // binding for the new symbol links and decodes query parameters correctly
    func testCaptureParsesRealUtmQueryStringThroughTheFfiBinding() {
        let store = UtmStore(defaults: defaults)
        let attributes = store.capture(url: "https://x.com/?utm_source=google&utm_campaign=bf")

        XCTAssertEqual(attributes["utm_source"], .string("google"))
        XCTAssertEqual(attributes["utm_campaign"], .string("bf"))
        XCTAssertEqual(attributes["utm_source_last"], .string("google"))
        XCTAssertEqual(attributes["utm_campaign_last"], .string("bf"))
    }
}
