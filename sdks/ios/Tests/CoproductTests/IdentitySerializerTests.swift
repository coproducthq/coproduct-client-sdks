import XCTest
@testable import Coproduct

// The synchronous identity API is fire-and-forget, so its calls must still be
// applied in the order they were made. The serializer is what guarantees that,
// independent of how long any single mutation takes
final class IdentitySerializerTests: XCTestCase {
    private actor Recorder {
        private(set) var order: [Int] = []
        func record(_ value: Int) { order.append(value) }
        var count: Int { order.count }
    }

    func testEnqueuePreservesCallOrderEvenWhenEarlierWorkIsSlower() async throws {
        let serializer = IdentitySerializer()
        let recorder = Recorder()
        let total = 10

        // Earlier items sleep longer. Without serialization the shorter later
        // items would finish first and the recorded order would be inverted
        for index in 0 ..< total {
            serializer.enqueue {
                let delayMillis = UInt64((total - index) * 2)
                try? await Task.sleep(nanoseconds: delayMillis * 1_000_000)
                await recorder.record(index)
            }
        }

        let deadline = Date().addingTimeInterval(2.0)
        while await recorder.count < total, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let order = await recorder.order
        XCTAssertEqual(order, Array(0 ..< total), "identity mutations must apply in call order")
    }
}
