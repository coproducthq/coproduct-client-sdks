import Foundation
#if canImport(UIKit)
import UIKit
#endif

// iOS polling trigger. Owns a repeating dispatch source timer plus an optional
// foreground-active notification observer. The fire closure drives a poll, typically wired to
// CoproductClient.pollNow(). The foreground fast path lets a backgrounded app
// refresh flags the moment it returns to the foreground rather
// than waiting for the next scheduled tick
final class HostTimer: @unchecked Sendable {
    static let didBecomeActiveNotification: Notification.Name = {
        #if canImport(UIKit)
        return UIApplication.didBecomeActiveNotification
        #else
        return Notification.Name("HostTimerDidBecomeActiveTestNotification")
        #endif
    }()

    private let interval: TimeInterval
    private let pollOnForeground: Bool
    private let fire: @Sendable () -> Void
    private var timer: DispatchSourceTimer?
    private var foregroundObserver: NSObjectProtocol?
    private let lock = NSLock()

    // A dedicated serial queue drives the repeating timer. A dispatch source
    // timer fires independently of main run loop pumping, so polling stays
    // reliable even while the app is mid-gesture or otherwise not spinning the
    // main run loop in a default mode
    private let queue = DispatchQueue(label: "app.coproduct.host-timer")

    init(interval: TimeInterval, pollOnForeground: Bool = true, _ fire: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.pollOnForeground = pollOnForeground
        self.fire = fire
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        if timer != nil { return }

        let fire = self.fire
        let source = DispatchSource.makeTimerSource(queue: queue)
        // Fire the first tick immediately so the initial poll starts as soon as
        // the client exists. The core does not poll during initialize, so the
        // host owns the first fetch as well as the recurring schedule
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { fire() }
        source.resume()
        timer = source

        if pollOnForeground {
            // At launch this foreground fire can coincide with the immediate
            // first tick above, issuing two polls within milliseconds. The core
            // coalesces them through its in-flight guard, so the redundant fetch
            // is dropped rather than duplicated
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: Self.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in fire() }
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
    }

    deinit {
        stop()
    }
}
