import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One-shot GPS acquisition. `CLLocationManager` reports through a delegate, so
/// this bridges `requestLocation()` to a single `async` call, requesting
/// when-in-use authorization first. Returns `nil` when permission is absent or
/// the OS cannot produce a fix, so the caller leaves `device_location` unset.
@MainActor
final class LocationAcquirer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(Double, Double)?, Never>?

    func requestPermission() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            let requester = AuthorizationRequester(manager: manager)
            _ = await requester.requestAndAwaitDecision()
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    func acquire() async -> (Double, Double)? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            let fix = coordinate.map { ($0.latitude, $0.longitude) }
            continuation?.resume(returning: fix)
            continuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        NSLog("[Coproduct] failed to read location: \(error.localizedDescription)")
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}

/// Bridges `CLLocationManager`'s authorization delegate callback to one `async`
/// call, matching the onboarding PermissionBridge's requester.
@MainActor
private final class AuthorizationRequester: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    init(manager: CLLocationManager) {
        self.manager = manager
        super.init()
    }

    func requestAndAwaitDecision() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in
            continuation?.resume(returning: status)
            continuation = nil
        }
    }
}

/// Drives foreground GPS refresh, porting the HostTimer shape (a self-
/// rescheduling dispatch-source timer plus app-state observers) but foreground-
/// ONLY: the loop pauses when the app backgrounds and resumes, with a fresh fix,
/// when it returns. Each tick reads one fix and hands it to `onFix`, which
/// publishes `device_location` so a geo-fence re-evaluates. The SDK holds no
/// continuous `CLLocationManager` subscription; it reads one fix per tick on the
/// host's cadence.
final class LocationMonitor: @unchecked Sendable {
    /// Interval used when the host enables location without naming one.
    static let defaultInterval: TimeInterval = 120
    /// Smallest repeating interval, so an over-eager caller cannot drain the battery.
    static let minInterval: TimeInterval = 30

    static func clampInterval(_ seconds: TimeInterval) -> TimeInterval {
        if seconds <= 0 { return 0 }
        return max(seconds, minInterval)
    }

    private let onFix: @Sendable (Double, Double) -> Void
    private let acquirer = LocationAcquirer()

    private var interval: TimeInterval = LocationMonitor.defaultInterval
    private var enabled = false
    private var paused = false
    private var stopped = false
    private var acquiring = false
    private var timer: DispatchSourceTimer?
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.coproduct.location-monitor")

    init(onFix: @escaping @Sendable (Double, Double) -> Void) {
        self.onFix = onFix
    }

    /// Request permission and, if granted, turn location on. Returns whether
    /// permission was granted. Idempotent: a second call does not re-prompt once
    /// authorized or restart the loop.
    func enable() async -> Bool {
        let granted = await acquirer.requestPermission()
        guard granted else { return false }
        lock.lock()
        let shouldStart = !enabled && !stopped
        if shouldStart {
            enabled = true
            paused = false
            observeAppState()
        }
        lock.unlock()
        if shouldStart { await tick() }
        return true
    }

    /// Enable (requesting permission) and set the repeating interval. `0` keeps
    /// only the one-shot fix. Returns whether permission was granted.
    func setInterval(_ seconds: TimeInterval) async -> Bool {
        let clamped = Self.clampInterval(seconds)
        lock.lock()
        interval = clamped
        lock.unlock()
        let granted = await enable()
        if granted { reschedule() }
        return granted
    }

    /// On-demand fix, ignored until the host has enabled location.
    func refreshNow() async {
        lock.lock()
        let active = enabled && !stopped
        lock.unlock()
        if active { await tick() }
    }

    func cancel() {
        lock.lock()
        stopped = true
        enabled = false
        timer?.cancel()
        timer = nil
        let foreground = foregroundObserver
        let background = backgroundObserver
        foregroundObserver = nil
        backgroundObserver = nil
        lock.unlock()
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
        if let background { NotificationCenter.default.removeObserver(background) }
    }

    private func observeAppState() {
        #if canImport(UIKit)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in self?.resume() }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in self?.pause() }
        #endif
    }

    private func pause() {
        lock.lock()
        paused = true
        timer?.cancel()
        timer = nil
        lock.unlock()
    }

    private func resume() {
        lock.lock()
        let shouldResume = enabled && !stopped && paused
        if shouldResume { paused = false }
        lock.unlock()
        if shouldResume { Task { await tick() } }
    }

    private func reschedule() {
        lock.lock()
        timer?.cancel()
        timer = nil
        guard enabled, !stopped, !paused, interval > 0 else {
            lock.unlock()
            return
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval)
        source.setEventHandler { [weak self] in Task { await self?.tick() } }
        timer = source
        source.resume()
        lock.unlock()
    }

    private func tick() async {
        lock.lock()
        if stopped || acquiring {
            lock.unlock()
            return
        }
        acquiring = true
        lock.unlock()

        let fix = await acquirer.acquire()

        lock.lock()
        acquiring = false
        let alive = !stopped
        lock.unlock()

        if alive, let fix { onFix(fix.0, fix.1) }
        reschedule()
    }
}
