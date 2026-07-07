import CoproductFFI
import XCTest
@testable import Coproduct

final class HostTimerTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            n += 1
            return n
        }
    }

    func testTimerRepollsAfterASuccessfulOutcome() async {
        let expectation = XCTestExpectation(description: "timer tick")
        expectation.expectedFulfillmentCount = 2
        expectation.assertForOverFulfill = false
        let timer = HostTimer(interval: 0.05) {
            expectation.fulfill()
            return .updated
        }
        timer.start()
        await fulfillment(of: [expectation], timeout: 1.0)
        timer.stop()
    }

    func testForegroundTriggersAPollDuringNormalCadence() async {
        let counter = Counter()
        let firstPoll = XCTestExpectation(description: "start poll")
        let foregroundPoll = XCTestExpectation(description: "foreground poll")
        // A long interval means the scheduled timer will not fire again within the
        // test, so the second poll can only come from the foreground event
        let timer = HostTimer(interval: 60, pollOnForeground: true) {
            switch counter.increment() {
            case 1: firstPoll.fulfill()
            case 2: foregroundPoll.fulfill()
            default: break
            }
            return .updated
        }
        timer.start()
        await fulfillment(of: [firstPoll], timeout: 1.0)
        // Let the first poll's reschedule settle so the foreground is not deduped
        try? await Task.sleep(nanoseconds: 100_000_000)
        NotificationCenter.default.post(name: HostTimer.didBecomeActiveNotification, object: nil)
        await fulfillment(of: [foregroundPoll], timeout: 1.0)
        timer.stop()
    }

    func testNextDelayHonorsRetryAfterAndBacksOff() {
        let interval: TimeInterval = 60

        // A success or a retry polls again after the normal interval
        XCTAssertEqual(HostTimer.nextDelay(for: .updated, interval: interval), 60)
        XCTAssertEqual(HostTimer.nextDelay(for: .notModified, interval: interval), 60)
        XCTAssertEqual(HostTimer.nextDelay(for: .retrying, interval: interval), 60)

        // A 429 honors the server's retry-after, but never faster than normal
        XCTAssertEqual(HostTimer.nextDelay(for: .rateLimited(retryAfterSecs: 300), interval: interval), 300)
        XCTAssertEqual(HostTimer.nextDelay(for: .rateLimited(retryAfterSecs: 5), interval: interval), 60)

        // Only a stale provider backs off, to the stale interval (5x)
        XCTAssertEqual(HostTimer.nextDelay(for: .stale, interval: interval), 300)

        // A fatal provider stops polling
        XCTAssertNil(HostTimer.nextDelay(for: .fatal, interval: interval))
    }

    func testBackoffOutcomesGateForeground() {
        // These outcomes open a window a foreground event must wait out
        XCTAssertTrue(HostTimer.isBackoff(.rateLimited(retryAfterSecs: 30)))
        XCTAssertTrue(HostTimer.isBackoff(.stale))
        // These do not, so a foreground refreshes immediately. Retrying is normal
        // cadence, so a foreground refreshes during it as well
        XCTAssertFalse(HostTimer.isBackoff(.retrying))
        XCTAssertFalse(HostTimer.isBackoff(.updated))
        XCTAssertFalse(HostTimer.isBackoff(.notModified))
        XCTAssertFalse(HostTimer.isBackoff(.fatal))
    }
}
