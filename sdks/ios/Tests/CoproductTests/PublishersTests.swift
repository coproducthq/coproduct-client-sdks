import XCTest
import Combine
@testable import Coproduct

final class PublishersTests: XCTestCase {
    func testFlagObservationExposesAnyPublisher() {
        let observation = FlagObservation<Bool>.constant(false)
        let publisher: AnyPublisher<Bool, Never> = observation.publisher
        var received: [Bool] = []
        let cancellable = publisher.sink { received.append($0) }
        _ = cancellable
        XCTAssertEqual(received, [false])
    }

    func testPublisherDeliversSubsequentChanges() {
        let observation = FlagObservation<String>.constant("a")
        var received: [String] = []
        let cancellable = observation.publisher.sink { received.append($0) }
        observation.testOnlyPush("b")
        _ = cancellable
        XCTAssertEqual(received, ["a", "b"])
    }

    func testBundleObservationExposesAnyPublisher() {
        let observation = FlagBundleObservation.constant([:])
        let publisher: AnyPublisher<[String: FlagDetailValue], Never> = observation.publisher
        var received: [[String: FlagDetailValue]] = []
        let cancellable = publisher.sink { received.append($0) }
        _ = cancellable
        XCTAssertEqual(received, [[:]])
    }
}
