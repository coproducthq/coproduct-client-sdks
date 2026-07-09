import XCTest
@testable import Coproduct

final class SessionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "app.coproduct.tests.sessionstore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        SessionStore.resetProcessGuardForTesting()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        SessionStore.resetProcessGuardForTesting()
        super.tearDown()
    }

    func testFirstSeenAtIsEpochSecondsWrittenOnce() {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let store = SessionStore(defaults: defaults)
        let first = store.sessionAttributes(now: t0)
        XCTAssertEqual(first["first_seen_at"], .number(1_760_000_000))

        // A later call, even from a fresh store in a fresh process, keeps the
        // original timestamp
        SessionStore.resetProcessGuardForTesting()
        let later = SessionStore(defaults: defaults)
            .sessionAttributes(now: Date(timeIntervalSince1970: 1_770_000_000))
        XCTAssertEqual(later["first_seen_at"], .number(1_760_000_000))
    }

    func testFirstSeenAtReadsThroughAFractionalDoubleWithoutRewriting() {
        defaults.set(1_760_000_000.0, forKey: SessionStore.firstSeenKey)
        let store = SessionStore(defaults: defaults)
        let attributes = store.sessionAttributes()
        XCTAssertEqual(attributes["first_seen_at"], .number(1_760_000_000))

        // The stored value round-trips as an NSNumber, so the read-through must
        // not have rewritten it to now
        let stored = (defaults.object(forKey: SessionStore.firstSeenKey) as? NSNumber)?.intValue
        XCTAssertEqual(stored, 1_760_000_000)
    }

    func testSessionCountIncrementsOncePerProcess() {
        let store = SessionStore(defaults: defaults)
        XCTAssertEqual(store.sessionAttributes()["session_count"], .number(1))

        // Same process: a second initialize (new store instance) must not
        // re-increment, because one session is one OS process lifetime
        XCTAssertEqual(
            SessionStore(defaults: defaults).sessionAttributes()["session_count"],
            .number(1)
        )

        // Simulated new process start increments
        SessionStore.resetProcessGuardForTesting()
        XCTAssertEqual(
            SessionStore(defaults: defaults).sessionAttributes()["session_count"],
            .number(2)
        )
    }
}
