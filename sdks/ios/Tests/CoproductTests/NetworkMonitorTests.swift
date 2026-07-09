import XCTest
@testable import Coproduct

final class NetworkMonitorTests: XCTestCase {
    func testClassifierVocabulary() {
        XCTAssertEqual(NetworkTypeClassifier.classify(satisfied: false, wifi: false, cellular: false, ethernet: false), "none")
        // An unsatisfied path is none even when an interface is nominally present
        XCTAssertEqual(NetworkTypeClassifier.classify(satisfied: false, wifi: true, cellular: false, ethernet: false), "none")
        XCTAssertEqual(NetworkTypeClassifier.classify(satisfied: true, wifi: true, cellular: false, ethernet: false), "wifi")
        XCTAssertEqual(NetworkTypeClassifier.classify(satisfied: true, wifi: false, cellular: true, ethernet: false), "cellular")
        XCTAssertEqual(NetworkTypeClassifier.classify(satisfied: true, wifi: false, cellular: false, ethernet: true), "ethernet")
        // Online but unclassified is other, a different fact from none
        XCTAssertEqual(NetworkTypeClassifier.classify(satisfied: true, wifi: false, cellular: false, ethernet: false), "other")
        // wifi wins when several interfaces report, matching the checking order
        XCTAssertEqual(NetworkTypeClassifier.classify(satisfied: true, wifi: true, cellular: true, ethernet: true), "wifi")
    }

    func testMonitorClassifiesDedupsAndPropagatesLifecycle() {
        var reported: [String] = []
        let source = FakePathSource()
        let monitor = NetworkMonitor(source: source, onChange: { reported.append($0) })

        monitor.start()
        XCTAssertTrue(source.started, "start reaches the source")

        source.emit(satisfied: true, wifi: true)
        source.emit(satisfied: true, wifi: true)
        source.emit(satisfied: true, cellular: true)
        source.emit(satisfied: false)
        XCTAssertEqual(reported, ["wifi", "cellular", "none"], "classified, deduplicated, in order")

        monitor.cancel()
        XCTAssertTrue(source.cancelled, "cancel reaches the source")
    }
}
