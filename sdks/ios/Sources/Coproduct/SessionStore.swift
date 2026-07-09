import Foundation

// Persists first_seen_at and session_count in UserDefaults, which participates
// in device backup by design: the values survive a device migration so cohort
// assignments stay stable. One session is one OS process lifetime, so the
// increment guard is process-global rather than per instance: shutdown plus
// re-initialize in the same process must not count a new session, and script
// reload lifecycles on other platforms follow the same rule
final class SessionStore {
    static let firstSeenKey = "app.coproduct.firstSeenAt"
    static let sessionCountKey = "app.coproduct.sessionCount"

    private static let guardLock = NSLock()
    private static var incrementedThisProcess = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Returns both persisted attributes, creating first_seen_at on the first
    // launch ever and incrementing session_count at most once per process.
    // first_seen_at is epoch integer seconds UTC: the platform has no date
    // operators, so absolute-time targeting uses the numeric operators against
    // an epoch value, and seconds stay exact in every binding's number type
    func sessionAttributes(now: Date = Date()) -> [String: AttributeValue] {
        Self.guardLock.lock()
        defer { Self.guardLock.unlock() }

        let firstSeen: Int
        if let existing = (defaults.object(forKey: Self.firstSeenKey) as? NSNumber)?.intValue {
            firstSeen = existing
        } else {
            firstSeen = Int(now.timeIntervalSince1970)
            defaults.set(firstSeen, forKey: Self.firstSeenKey)
        }

        var count = defaults.integer(forKey: Self.sessionCountKey)
        if !Self.incrementedThisProcess {
            count += 1
            defaults.set(count, forKey: Self.sessionCountKey)
            Self.incrementedThisProcess = true
        }

        return [
            "first_seen_at": .number(Double(firstSeen)),
            "session_count": .number(Double(count)),
        ]
    }

    static func resetProcessGuardForTesting() {
        guardLock.lock()
        defer { guardLock.unlock() }
        incrementedThisProcess = false
    }
}
