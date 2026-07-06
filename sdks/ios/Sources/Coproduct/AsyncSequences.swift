import Combine

// AsyncSequence binding. Lets callers write
// for await value in Coproduct.observe(...).values { ... }
// The stream is backed by the same seeded Combine publisher the observation
// exposes, so it yields the current value immediately and then every change.
// The Combine subscription is torn down when the stream terminates

public extension FlagObservation {
    var values: AsyncStream<T> {
        let publisher = self.publisher
        // Flags only need the latest value, so a slow consumer coalesces to it
        // rather than accumulating an unbounded backlog of intermediate changes
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cancellable = publisher.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

public extension FlagBundleObservation {
    var values: AsyncStream<[String: FlagDetailValue]> {
        let publisher = self.publisher
        // Coalesce to the latest snapshot for a slow consumer rather than
        // buffering every intermediate change
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cancellable = publisher.sink { snapshot in
                continuation.yield(snapshot)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
