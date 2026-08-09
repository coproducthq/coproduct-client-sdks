import XCTest
@testable import Coproduct

final class AsyncSequencesTests: XCTestCase {
    func testValuesYieldsCurrentThenUpdates() async {
        let observation = FlagObservation<Bool>.constant(false)
        let collector = Task<[Bool], Never> {
            var received: [Bool] = []
            var iterator = observation.values.makeAsyncIterator()
            while received.count < 2, let next = await iterator.next() {
                received.append(next)
            }
            return received
        }

        // Give the iterator a chance to subscribe and yield the seed value
        // before pushing the update, so both values land in order
        try? await Task.sleep(nanoseconds: 50_000_000)
        observation.testOnlyPush(true)
        let received = await collector.value
        XCTAssertEqual(received, [false, true])
    }

    func testBundleValuesYieldsCurrentThenUpdates() async {
        let observation = FlagBundleObservation.constant([:])
        let collector = Task<Int, Never> {
            var count = 0
            var iterator = observation.values.makeAsyncIterator()
            while count < 2, await iterator.next() != nil {
                count += 1
            }
            return count
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        observation.testOnlyReplace(with: ["k": .bool(true)])
        let count = await collector.value
        XCTAssertEqual(count, 2)
    }
}
