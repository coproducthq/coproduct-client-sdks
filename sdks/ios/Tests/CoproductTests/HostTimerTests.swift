import XCTest
@testable import Coproduct

final class HostTimerTests: XCTestCase {
    func testTimerFiresOnScheduledInterval() async {
        let expectation = XCTestExpectation(description: "timer tick")
        expectation.expectedFulfillmentCount = 2
        let timer = HostTimer(interval: 0.05) {
            expectation.fulfill()
        }
        timer.start()
        await fulfillment(of: [expectation], timeout: 1.0)
        timer.stop()
    }

    func testForegroundNotificationTriggersImmediatePoll() {
        let expectation = XCTestExpectation(description: "foreground tick")
        let timer = HostTimer(interval: 60, pollOnForeground: true) {
            expectation.fulfill()
        }
        timer.start()
        NotificationCenter.default.post(name: HostTimer.didBecomeActiveNotification, object: nil)
        wait(for: [expectation], timeout: 1.0)
        timer.stop()
    }
}
