import CoproductFFI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// iOS polling trigger. Owns a self-rescheduling dispatch source timer plus an
// optional foreground-active notification observer. Each poll returns a
// PollOutcome that decides when the next poll fires, so the host honors the
// scheduling signal the core computes: a success or a retry polls again after the
// normal interval, a 429 waits out the server's retry-after, and only a stale
// provider backs off. The foreground fast path refreshes on return to the
// foreground during normal cadence, but respects an active back-off window rather
// than bypassing it
final class HostTimer: @unchecked Sendable {
    static let didBecomeActiveNotification: Notification.Name = {
        #if canImport(UIKit)
        return UIApplication.didBecomeActiveNotification
        #else
        return Notification.Name("HostTimerDidBecomeActiveTestNotification")
        #endif
    }()

    // A stale provider polls at this multiple of the normal interval, mirroring
    // the core's stale_retry_interval. Retrying stays at the normal cadence so a
    // transient failure recovers promptly within the retry budget
    static let backoffMultiplier: Double = 5

    private let interval: TimeInterval
    private let pollOnForeground: Bool
    private let poll: @Sendable () async -> PollOutcome
    private var timer: DispatchSourceTimer?
    private var foregroundObserver: NSObjectProtocol?
    private var stopped = false
    private var pollInFlight = false
    // Earliest time a foreground event may trigger an off-schedule poll. It sits
    // in the past during normal cadence, so a foreground refreshes immediately,
    // and in the future while backing off, so a foreground waits out the window
    private var earliestForegroundPoll: DispatchTime = .now()
    private let lock = NSLock()

    // A dedicated serial queue drives the timer. A dispatch source timer fires
    // independently of main run loop pumping, so polling stays reliable even while
    // the app is mid-gesture or otherwise not spinning the main run loop
    private let queue = DispatchQueue(label: "app.coproduct.host-timer")

    init(
        interval: TimeInterval,
        pollOnForeground: Bool = true,
        _ poll: @escaping @Sendable () async -> PollOutcome
    ) {
        self.interval = interval
        self.pollOnForeground = pollOnForeground
        self.poll = poll
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        if stopped || timer != nil { return }
        // Poll immediately on start: the core does not poll during initialize, so
        // the host owns the first fetch as well as the recurring schedule
        scheduleLocked(after: 0)

        if pollOnForeground {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: Self.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.foregroundFired() }
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        timer?.cancel()
        timer = nil
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
    }

    // Schedule a one-shot fire after `delay`. The timer reschedules itself from
    // each poll's outcome rather than repeating at a fixed cadence. Callers hold
    // the lock
    private func scheduleLocked(after delay: TimeInterval) {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: delay <= 0 ? .now() : .now() + delay)
        source.setEventHandler { [weak self] in self?.triggerPoll() }
        source.resume()
        timer = source
    }

    private func foregroundFired() {
        lock.lock()
        let allowed = !stopped && !pollInFlight && DispatchTime.now() >= earliestForegroundPoll
        lock.unlock()
        if allowed { triggerPoll() }
    }

    // Run one poll, unless one is already in flight, and reschedule from its
    // outcome once it completes
    private func triggerPoll() {
        lock.lock()
        if stopped || pollInFlight {
            lock.unlock()
            return
        }
        pollInFlight = true
        let poll = self.poll
        lock.unlock()

        Task {
            let outcome = await poll()
            self.rescheduleAfterPoll(outcome)
        }
    }

    private func rescheduleAfterPoll(_ outcome: PollOutcome) {
        lock.lock()
        defer { lock.unlock() }
        pollInFlight = false
        if stopped { return }
        guard let delay = Self.nextDelay(for: outcome, interval: interval) else {
            // A fatal provider is terminal, so stop scheduling further polls
            timer?.cancel()
            timer = nil
            return
        }
        // A foreground bypasses the wait during normal cadence, but must wait out
        // an active back-off window
        earliestForegroundPoll = Self.isBackoff(outcome) ? .now() + delay : .now()
        scheduleLocked(after: delay)
    }

    // The delay before the next poll for a given outcome. A `nil` result stops
    // polling. A 429 honors the server's retry-after but never polls faster than
    // the normal interval. Retrying stays at the normal cadence, which is the
    // core's short recovery window (its retry budget reaches Stale at the intended
    // time), and only a stale provider backs off
    static func nextDelay(for outcome: PollOutcome, interval: TimeInterval) -> TimeInterval? {
        switch outcome {
        case .updated, .notModified, .retrying, .dedupedSkipped:
            return interval
        case let .rateLimited(retryAfterSecs):
            return max(TimeInterval(retryAfterSecs), interval)
        case .stale:
            return interval * backoffMultiplier
        case .fatal:
            return nil
        }
    }

    // Whether an outcome opens a back-off window that a foreground event must
    // wait out rather than bypass. Retrying is normal cadence, so a foreground
    // refreshes during it
    static func isBackoff(_ outcome: PollOutcome) -> Bool {
        switch outcome {
        case .rateLimited, .stale:
            return true
        case .updated, .notModified, .retrying, .dedupedSkipped, .fatal:
            return false
        }
    }

    deinit {
        stop()
    }
}
