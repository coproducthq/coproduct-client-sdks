import UIKit
import Flutter
import XCTest

@testable import coproduct

final class DeviceClassifierTests: XCTestCase {
    func testPhoneIdiom() {
        XCTAssertEqual(DeviceClassifier.deviceType(for: .phone), "phone")
    }

    func testPadIdiom() {
        XCTAssertEqual(DeviceClassifier.deviceType(for: .pad), "tablet")
    }

    func testTelevisionIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .tv))
    }

    func testCarPlayIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .carPlay))
    }

    func testMacIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .mac))
    }

    func testUnspecifiedIdiomOmits() {
        XCTAssertNil(DeviceClassifier.deviceType(for: .unspecified))
    }
}

/// An in-memory store with the failure modes the real one has. It also records
/// how many callers are inside it at once: with holdFirstRead set, the first
/// access waits until a second access arrives or the bound passes, so two
/// callers that are not serialized are guaranteed to overlap
final class FakeSessionStorage: SessionStorage {
    var isAvailable = true
    var record: Any?
    var dropWrites = false
    var transform: (([String: Any]) -> [String: Any])?
    var holdFirstRead: TimeInterval = 0
    // When set, every access checks that the caller holds it, which proves
    // serialization without depending on how threads are scheduled. try()
    // fails while the lock is held, and succeeding means nobody held it
    var lock: NSLock?

    private let counters = NSLock()
    private var _unlockedAccesses = 0
    private var inFlight = 0
    private var entries = 0
    private var _writes = 0
    private var _reads = 0
    private var _maxInFlight = 0
    private let secondArrived = DispatchSemaphore(value: 0)

    var writes: Int { counters.lock(); defer { counters.unlock() }; return _writes }
    var reads: Int { counters.lock(); defer { counters.unlock() }; return _reads }
    var maxInFlight: Int { counters.lock(); defer { counters.unlock() }; return _maxInFlight }
    var unlockedAccesses: Int { counters.lock(); defer { counters.unlock() }; return _unlockedAccesses }

    private func enter() -> Int {
        var unlocked = false
        if let lock, lock.try() {
            unlocked = true
            lock.unlock()
        }
        counters.lock()
        if unlocked { _unlockedAccesses += 1 }
        inFlight += 1
        _maxInFlight = max(_maxInFlight, inFlight)
        entries += 1
        let entry = entries
        counters.unlock()
        if entry == 2 { secondArrived.signal() }
        return entry
    }

    private func leave() {
        counters.lock()
        inFlight -= 1
        counters.unlock()
    }

    func read() -> Any? {
        let entry = enter()
        defer { leave() }
        counters.lock()
        _reads += 1
        counters.unlock()
        if entry == 1, holdFirstRead > 0 {
            _ = secondArrived.wait(timeout: .now() + holdFirstRead)
        }
        return record
    }

    func write(_ value: [String: Any]) {
        _ = enter()
        defer { leave() }
        counters.lock()
        _writes += 1
        counters.unlock()
        if dropWrites { return }
        record = transform?(value) ?? value
    }
}

final class SessionStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private var suiteName = ""
    private var defaults: UserDefaults!
    // One per test, standing in for one OS process. The tests run inside the
    // example app, which initializes the SDK at launch and so uses the shared
    // state, which is why no test here touches it
    private var process = SessionProcessState()

    override func setUp() {
        super.setUp()
        process = SessionProcessState()
        suiteName = "SessionStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        for fake in wired {
            XCTAssertEqual(fake.unlockedAccesses, 0, "an access did not hold the process lock")
        }
        wired = []
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // Every fake a test wires up, so each is checked for unlocked access
    private var wired: [FakeSessionStorage] = []

    private func store(_ storage: SessionStorage, at date: Date? = nil) -> SessionStore {
        let when = date ?? now
        if let fake = storage as? FakeSessionStorage {
            fake.lock = process.lock
            if !wired.contains(where: { $0 === fake }) { wired.append(fake) }
        }
        return SessionStore(storage: storage, process: process, now: { when })
    }

    func testFirstLaunchCreatesBothValues() {
        let storage = FakeSessionStorage()
        XCTAssertEqual(store(storage).begin(), SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1))
    }

    func testASecondCallerInTheSameProcessDoesNotIncrement() {
        let storage = FakeSessionStorage()
        _ = store(storage).begin()
        XCTAssertEqual(store(storage, at: now.addingTimeInterval(60)).begin()?.sessionCount, 1)
        XCTAssertEqual(storage.writes, 1)
    }

    func testANewProcessIncrementsOnceAndKeepsFirstSeen() {
        let storage = FakeSessionStorage()
        _ = store(storage).begin()
        process = SessionProcessState() // the process relaunches
        XCTAssertEqual(
            store(storage, at: now.addingTimeInterval(3_600)).begin(),
            SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 2)
        )
    }

    func testTheDefaultStateIsTheSharedOne() {
        // Production passes no state, so this is the wiring that makes two
        // engines' plugin instances contend for one guard. Identity only: the
        // shared state itself belongs to the example app's own initialize
        XCTAssertTrue(SessionStore(storage: FakeSessionStorage()).process === SessionProcessState.shared)
    }

    func testConcurrentCallersAreSerializedAndAgree() {
        // Every access records whether the caller holds the process lock, which
        // fails deterministically without it however the threads are scheduled.
        // The held first read makes an unserialized overlap likely as well
        let storage = FakeSessionStorage()
        storage.holdFirstRead = 0.5
        storage.lock = process.lock
        wired.append(storage)
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [SessionPair?] = []
        for _ in 0..<2 {
            DispatchQueue.global().async(group: group) {
                let pair = SessionStore(storage: storage, process: self.process, now: { self.now }).begin()
                lock.lock()
                results.append(pair)
                lock.unlock()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(storage.unlockedAccesses, 0)
        XCTAssertEqual(storage.maxInFlight, 1)
        XCTAssertEqual(storage.writes, 1)
        XCTAssertEqual(results, [
            SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1),
            SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1),
        ])
    }

    func testARecordClearedAfterTheCountDoesNotStartASecondTransaction() {
        let storage = FakeSessionStorage()
        let first = store(storage).begin()
        XCTAssertEqual(first, SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1))
        storage.record = nil // the app clears its data mid-process
        XCTAssertEqual(store(storage, at: now.addingTimeInterval(60)).begin(), first)
        storage.record = "garbage"
        XCTAssertEqual(store(storage, at: now.addingTimeInterval(120)).begin(), first)
        XCTAssertEqual(storage.writes, 1)
    }

    func testValuesAreBoundedToWhatADoubleHoldsExactly() {
        let max = SessionStore.maxExact
        func begin(_ first: Any, _ count: Any) -> SessionPair? {
            process = SessionProcessState()
            let storage = FakeSessionStorage()
            storage.record = [SessionStore.firstSeenAtField: first, SessionStore.sessionCountField: count]
            return store(storage).begin()
        }
        let restarted = SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1)
        XCTAssertEqual(begin(NSNumber(value: max), 41), SessionPair(firstSeenAt: max, sessionCount: 42))
        XCTAssertEqual(begin(0, 41), SessionPair(firstSeenAt: 0, sessionCount: 42))
        XCTAssertEqual(begin(NSNumber(value: max + 1), 41), restarted)
        XCTAssertEqual(
            begin(1_600_000_000, NSNumber(value: max - 1)),
            SessionPair(firstSeenAt: 1_600_000_000, sessionCount: max)
        )
        // The largest rejected count: incrementing it would leave the exact range
        XCTAssertEqual(begin(1_600_000_000, NSNumber(value: max)), restarted)
        // Would trap on the increment if it were accepted
        XCTAssertEqual(begin(1_600_000_000, NSNumber(value: Int64.max)), restarted)
    }

    func testAReadBackWithoutTheRecordOmitsForThisAndEveryLaterCaller() {
        let storage = FakeSessionStorage()
        storage.dropWrites = true
        XCTAssertNil(store(storage).begin())
        storage.dropWrites = false
        XCTAssertNil(store(storage).begin())
        XCTAssertEqual(storage.writes, 1)
    }

    func testAnUnavailableStoreOmitsWithoutTouchingItAndLatches() {
        let storage = FakeSessionStorage()
        storage.isAvailable = false
        storage.record = [SessionStore.firstSeenAtField: 1_600_000_000, SessionStore.sessionCountField: 41]
        XCTAssertNil(store(storage).begin())
        XCTAssertEqual(storage.reads, 0)
        XCTAssertEqual(storage.writes, 0)
        storage.isAvailable = true
        XCTAssertNil(store(storage).begin(), "the failure sticks for the process")
        XCTAssertEqual(storage.writes, 0)
    }

    func testAPairAlreadyCountedIsReturnedEvenWhileTheStoreIsUnavailable() {
        // A second engine arriving while the store is unavailable must get the
        // pair this process already counted, not latch the process after it
        let storage = FakeSessionStorage()
        let first = store(storage).begin()
        XCTAssertNotNil(first)
        storage.isAvailable = false
        XCTAssertEqual(store(storage).begin(), first)
        XCTAssertEqual(storage.writes, 1)
    }

    func testTheDefaultsFileProbe() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("defaults.plist")

        XCTAssertTrue(DefaultsFile.isReadable(atPath: nil), "an unknown path counts as available")
        XCTAssertTrue(DefaultsFile.isReadable(atPath: file.path), "a missing file has nothing to overwrite")
        try Data("x".utf8).write(to: file)
        XCTAssertTrue(DefaultsFile.isReadable(atPath: file.path))
        // Unreadable the way a protected file is before first unlock
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        XCTAssertFalse(DefaultsFile.isReadable(atPath: file.path))
    }

    /// A file in a fresh temporary directory, removed with it by the returned
    /// cleanup. Written with [contents] when given, and made unreadable the way
    /// a protected file is before first unlock when [readable] is false
    private func defaultsFile(
        contents: [String: Any]? = nil,
        readable: Bool = true
    ) throws -> (path: String, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("defaults.plist").path
        if let contents {
            // Binary, the format the real defaults file uses
            let data = try PropertyListSerialization.data(
                fromPropertyList: contents, format: .binary, options: 0
            )
            try data.write(to: URL(fileURLWithPath: path))
        } else if !readable {
            try Data().write(to: URL(fileURLWithPath: path))
        }
        if !readable {
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        }
        return (path, {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    func testThePluginOmitsTheSessionWhileTheDefaultsFileIsUnreadable() throws {
        // A fresh state rather than the shared one, which the route test and
        // the example app's own initialize rely on
        let file = try defaultsFile(readable: false)
        defer { file.cleanup() }
        let plugin = CoproductHostContextPlugin(
            defaultsFilePath: file.path,
            sessionProcess: SessionProcessState()
        )
        let answered = expectation(description: "beginSession answered")
        plugin.handle(FlutterMethodCall(methodName: "beginSession", arguments: nil)) { result in
            XCTAssertNil(result)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
    }

    func testTheUserDefaultsAdapterWritesNothingWhileItsFileIsUnreadable() throws {
        let file = try defaultsFile(readable: false)
        defer { file.cleanup() }
        let storage = UserDefaultsSessionStorage(defaults: defaults, filePath: file.path)
        XCTAssertNil(store(storage).begin())
        XCTAssertNil(defaults.object(forKey: "app.coproduct.flutter.session"))
    }

    func testTheDefaultsFileLookupClassifiesEachFile() throws {
        let key = "app.coproduct.flutter.session"
        let missing = try defaultsFile()
        defer { missing.cleanup() }
        XCTAssertEqual(DefaultsFile.lookup(key, atPath: missing.path), .missing)

        let unreadable = try defaultsFile(readable: false)
        defer { unreadable.cleanup() }
        XCTAssertEqual(DefaultsFile.lookup(key, atPath: unreadable.path), .unreadable)

        let holding = try defaultsFile(contents: [key: ["firstSeenAt": 1, "sessionCount": 1]])
        defer { holding.cleanup() }
        XCTAssertEqual(DefaultsFile.lookup(key, atPath: holding.path), .holdsKey)

        let lacking = try defaultsFile(contents: ["someOtherSetting": true])
        defer { lacking.cleanup() }
        XCTAssertEqual(DefaultsFile.lookup(key, atPath: lacking.path), .lacksKey)

        // Unparseable, so it holds no record anyone could read back
        let garbage = try defaultsFile()
        defer { garbage.cleanup() }
        try Data("not a plist".utf8).write(to: URL(fileURLWithPath: garbage.path))
        XCTAssertEqual(DefaultsFile.lookup(key, atPath: garbage.path), .lacksKey)

        // Empty, so it too holds no record, and must not lock the store out
        let empty = try defaultsFile()
        defer { empty.cleanup() }
        try Data().write(to: URL(fileURLWithPath: empty.path))
        XCTAssertEqual(DefaultsFile.lookup(key, atPath: empty.path), .lacksKey)

        // A directory opens but cannot be read, the way a file locked between
        // the open and the read fails
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(DefaultsFile.lookup(key, atPath: directory.path), .unreadable)
    }

    func testTheDefaultsFileLookupClosesTheFileItOpens() throws {
        let file = try defaultsFile(contents: ["someOtherSetting": true])
        defer { file.cleanup() }
        let before = open("/dev/null", O_RDONLY)
        close(before)
        for _ in 0..<100 {
            _ = DefaultsFile.lookup("app.coproduct.flutter.session", atPath: file.path)
        }
        let after = open("/dev/null", O_RDONLY)
        close(after)
        XCTAssertEqual(after, before, "a descriptor leaked on each lookup")
    }

    func testARecordTheDefaultsHoldIsNotTrustedWhileItsFileIsUnreadable() throws {
        // The increment would not reach a file that cannot be read now
        defaults.set(
            ["firstSeenAt": 1_600_000_000, "sessionCount": 41],
            forKey: "app.coproduct.flutter.session"
        )
        let file = try defaultsFile(readable: false)
        defer { file.cleanup() }
        let storage = UserDefaultsSessionStorage(defaults: defaults, filePath: file.path)
        XCTAssertNil(store(storage).begin())
    }

    func testAStaleEmptyCacheOverARecordOnDiskIsNotTrusted() throws {
        // The defaults report no record, but the file they are kept in holds
        // one, which is what a cache read before first unlock looks like
        let file = try defaultsFile(contents: [
            "app.coproduct.flutter.session": ["firstSeenAt": 1_600_000_000, "sessionCount": 41],
        ])
        defer { file.cleanup() }
        let storage = UserDefaultsSessionStorage(defaults: defaults, filePath: file.path)
        XCTAssertNil(store(storage).begin())
        XCTAssertNil(defaults.object(forKey: "app.coproduct.flutter.session"))
    }

    func testAFirstLaunchWithOtherDefaultsOnDiskStillCounts() throws {
        let file = try defaultsFile(contents: ["someOtherSetting": true])
        defer { file.cleanup() }
        let storage = UserDefaultsSessionStorage(defaults: defaults, filePath: file.path)
        XCTAssertEqual(store(storage).begin(), SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1))
    }

    func testARecordTheDefaultsHoldIsTrustedWhateverTheFileShows() throws {
        // The file is only consulted when the defaults report no record. On an
        // ordinary later launch both hold one, and a record written in this
        // process may not have reached the file yet, so the defaults win
        defaults.set(
            ["firstSeenAt": 1_600_000_000, "sessionCount": 41],
            forKey: "app.coproduct.flutter.session"
        )
        let file = try defaultsFile(contents: [
            "app.coproduct.flutter.session": ["firstSeenAt": 1_500_000_000, "sessionCount": 7],
        ])
        defer { file.cleanup() }
        let storage = UserDefaultsSessionStorage(defaults: defaults, filePath: file.path)
        XCTAssertEqual(store(storage).begin(), SessionPair(firstSeenAt: 1_600_000_000, sessionCount: 42))
    }

    func testAPropertyListExistsAtTheStandardPath() throws {
        // Where UserDefaults keeps its file is not documented, and a wrong path
        // reads as missing, which counts as available and silently turns the
        // guard off. Writing a key makes sure the file is created. The daemon
        // flushes on its own schedule, so the key reaching the file is the fast
        // path, and what is asserted is that a property list is there at all
        let key = "app.coproduct.flutter.pathcheck.\(UUID().uuidString)"
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.synchronize()
        let path = try XCTUnwrap(DefaultsFile.standardPath)
        let deadline = Date().addingTimeInterval(30)
        while NSDictionary(contentsOfFile: path)?[key] == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertNotNil(
            NSDictionary(contentsOfFile: path),
            "no defaults property list at \(path)"
        )
    }

    func testAConfirmedCountBeyondTheExactRangeOmitsAndLatches() {
        let storage = FakeSessionStorage()
        storage.transform = { record in
            var changed = record
            changed[SessionStore.sessionCountField] = NSNumber(value: SessionStore.maxExact + 1)
            return changed
        }
        XCTAssertNil(store(storage).begin())
        storage.transform = nil
        XCTAssertNil(store(storage).begin())
    }

    func testAWholeDoubleCountIsAccepted() {
        // A plist number keeps no storage type, so iOS reads a whole 7.0 as 7
        // where Android, whose file keeps the Long type, would restart. Only a
        // writer other than this SDK can store one
        let storage = FakeSessionStorage()
        storage.record = [SessionStore.firstSeenAtField: 1_600_000_000, SessionStore.sessionCountField: 7.0]
        XCTAssertEqual(store(storage).begin(), SessionPair(firstSeenAt: 1_600_000_000, sessionCount: 8))
    }

    func testThePairReturnedIsWhatTheStoreHolds() {
        let storage = FakeSessionStorage()
        storage.transform = { record in
            var changed = record
            changed[SessionStore.sessionCountField] = NSNumber(value: Int64(11))
            return changed
        }
        XCTAssertEqual(store(storage).begin()?.sessionCount, 11)
    }

    func testCorruptRecordsRestartRatherThanPublishing() {
        let corrupt: [Any] = [
            "not a dictionary",
            [SessionStore.firstSeenAtField: "yesterday", SessionStore.sessionCountField: 7],
            [SessionStore.firstSeenAtField: 1_600_000_000.5, SessionStore.sessionCountField: 7],
            [SessionStore.firstSeenAtField: -5, SessionStore.sessionCountField: 7],
            [SessionStore.firstSeenAtField: 1_600_000_000, SessionStore.sessionCountField: 0],
            [SessionStore.firstSeenAtField: 1_600_000_000, SessionStore.sessionCountField: true],
            [SessionStore.firstSeenAtField: 1_600_000_000],
        ]
        for record in corrupt {
            process = SessionProcessState()
            let storage = FakeSessionStorage()
            storage.record = record
            XCTAssertEqual(
                store(storage).begin(),
                SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1),
                "\(record)"
            )
        }
    }

    func testAWrongTypedOrMissingCountIsCorrupt() {
        // The count is validated on its own, not only through first_seen_at
        let counts: [Any?] = ["7", 7.5, true, nil]
        for count in counts {
            process = SessionProcessState()
            let storage = FakeSessionStorage()
            var record: [String: Any] = [SessionStore.firstSeenAtField: 1_600_000_000]
            if let count { record[SessionStore.sessionCountField] = count }
            storage.record = record
            XCTAssertEqual(
                store(storage).begin(),
                SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1),
                "\(String(describing: count))"
            )
        }
    }

    func testTheUserDefaultsAdapterWritesOneRecordUnderTheDocumentedKey() {
        _ = store(UserDefaultsSessionStorage(defaults: defaults, filePath: nil)).begin()
        // One key and one two-field record, because two keys could be split by
        // a crash between writes
        XCTAssertEqual(
            defaults.persistentDomain(forName: suiteName).map { Set($0.keys) },
            ["app.coproduct.flutter.session"]
        )
        let record = defaults.dictionary(forKey: "app.coproduct.flutter.session")
        XCTAssertEqual(record?.count, 2)
        XCTAssertEqual(record?["firstSeenAt"] as? Int64, 1_767_225_600)
        XCTAssertEqual(record?["sessionCount"] as? Int64, 1)
    }

    func testAnExistingRecordSurvivesAnUpgrade() {
        defaults.set(
            ["firstSeenAt": 1_600_000_000, "sessionCount": 41],
            forKey: "app.coproduct.flutter.session"
        )
        XCTAssertEqual(
            store(UserDefaultsSessionStorage(defaults: defaults, filePath: nil)).begin(),
            SessionPair(firstSeenAt: 1_600_000_000, sessionCount: 42)
        )
    }

    func testTheNativeSdkKeysAreNeverReadOrWritten() {
        defaults.set(1_500_000_000, forKey: "app.coproduct.firstSeenAt")
        defaults.set(99, forKey: "app.coproduct.sessionCount")
        XCTAssertEqual(
            store(UserDefaultsSessionStorage(defaults: defaults, filePath: nil)).begin(),
            SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 1)
        )
        XCTAssertEqual(defaults.integer(forKey: "app.coproduct.firstSeenAt"), 1_500_000_000)
        XCTAssertEqual(defaults.integer(forKey: "app.coproduct.sessionCount"), 99)
    }

    func testThePluginRoutesBeginSession() throws {
        // Without the route the Dart side would see a missing method, and only
        // a device run would notice. Two plugin instances stand in for two
        // engines: they must share the process state and the standard defaults,
        // and each must answer on main where Flutter expects it. The pair comes
        // from the shared state the example app's own initialize also uses, so
        // its values are compared rather than predicted
        var answers: [Any?] = []
        for _ in 0..<2 {
            let answered = expectation(description: "beginSession answered")
            CoproductHostContextPlugin().handle(
                FlutterMethodCall(methodName: "beginSession", arguments: nil)
            ) { result in
                XCTAssertTrue(Thread.isMainThread, "answered off the main thread")
                XCTAssertFalse(result as AnyObject === FlutterMethodNotImplemented)
                answers.append(result)
                answered.fulfill()
            }
            wait(for: [answered], timeout: 5)
        }
        // A pair is required rather than tolerated: the test host is a fresh
        // process, so nothing has latched, and the simulator's defaults file is
        // readable
        XCTAssertEqual(answers.count, 2)
        let first = try XCTUnwrap(answers.first as? [String: NSNumber])
        XCTAssertEqual(answers.last as? [String: NSNumber], first, "two engines saw different pairs")
        let record = UserDefaults.standard.dictionary(forKey: "app.coproduct.flutter.session")
        XCTAssertEqual((record?["firstSeenAt"] as? NSNumber)?.int64Value, first["first_seen_at"]?.int64Value)
        XCTAssertEqual((record?["sessionCount"] as? NSNumber)?.int64Value, first["session_count"]?.int64Value)
    }

    func testTheChannelShapeCarriesBothNumbers() {
        let value = SessionPair(firstSeenAt: 1_767_225_600, sessionCount: 3).channelValue
        XCTAssertEqual(value["first_seen_at"]?.int64Value, 1_767_225_600)
        XCTAssertEqual(value["session_count"]?.int64Value, 3)
        XCTAssertEqual(value.count, 2)
        // A floating-point number reaches Dart as a double, which the Dart
        // validator rejects, dropping the pair
        for number in value.values {
            XCTAssertFalse(CFNumberIsFloatType(number), "\(number) is floating point")
        }
    }
}

private let wifiPath = NetworkPathFacts(satisfied: true, wifi: true, cellular: false, ethernet: false)
private let cellularPath = NetworkPathFacts(satisfied: true, wifi: false, cellular: true, ethernet: false)
private let offlinePath = NetworkPathFacts(satisfied: false, wifi: false, cellular: false, ethernet: false)

/// Reads one event as "epoch:value", or nil when it is not the envelope
private func decoded(_ event: Any?) -> String? {
    guard let map = event as? [String: Any],
          let epoch = map["epoch"] as? NSNumber,
          let value = map["value"] as? String else { return nil }
    return "\(epoch.int64Value):\(value)"
}

/// Stands in for NWPathMonitor. It delivers nothing on its own: a test calls
/// deliver, which is what the real monitor's main-queue update amounts to, and
/// it keeps delivering after cancel, which is what an update already in flight
/// does
final class FakePathSource: NetworkPathSource {
    private(set) var starts = 0
    private(set) var cancels = 0
    private var onUpdate: ((NetworkPathFacts) -> Void)?

    /// Delivered from within cancel(), after the cancel count increments, so a
    /// test can reproduce a source that delivers while it is being cancelled
    var deliverOnCancel: NetworkPathFacts?

    func start(onUpdate: @escaping (NetworkPathFacts) -> Void) {
        starts += 1
        self.onUpdate = onUpdate
    }

    func cancel() {
        cancels += 1
        if let facts = deliverOnCancel {
            onUpdate?(facts)
        }
    }

    func deliver(_ facts: NetworkPathFacts) {
        onUpdate?(facts)
    }
}

/// Records every event a sink received, in order
final class RecordingEventSink {
    private(set) var events: [Any?] = []
    lazy var sink: FlutterEventSink = { [unowned self] event in self.events.append(event) }
    var values: [String] { events.compactMap(decoded) }
    var errorCodes: [String] { events.compactMap { ($0 as? FlutterError)?.code } }
}

final class NetworkTypeClassifierTests: XCTestCase {
    func testEveryCombinationMatchesTheIOSSDKPrecedence() {
        // The iOS SDK's order, restated as a table, so one physical network maps
        // the same way through either SDK
        for satisfied in [false, true] {
            for wifi in [false, true] {
                for cellular in [false, true] {
                    for ethernet in [false, true] {
                        let expected: String
                        if !satisfied { expected = "none" }
                        else if wifi { expected = "wifi" }
                        else if cellular { expected = "cellular" }
                        else if ethernet { expected = "ethernet" }
                        else { expected = "other" }
                        let facts = NetworkPathFacts(
                            satisfied: satisfied, wifi: wifi, cellular: cellular, ethernet: ethernet)
                        XCTAssertEqual(NetworkTypeClassifier.classify(facts), expected, "\(facts)")
                    }
                }
            }
        }
    }

    func testConnectedThroughNoKnownInterfaceIsOtherNeverNone() {
        let facts = NetworkPathFacts(satisfied: true, wifi: false, cellular: false, ethernet: false)
        XCTAssertEqual(NetworkTypeClassifier.classify(facts), "other")
    }
}

final class NetworkTypeObserverTests: XCTestCase {
    private var sources: [FakePathSource] = []

    override func setUp() {
        super.setUp()
        sources = []
    }

    private func makeObserver() -> NetworkTypeObserver {
        NetworkTypeObserver(makeSource: { [unowned self] in
            let source = FakePathSource()
            self.sources.append(source)
            return source
        })
    }

    func testTheCurrentPathIsReportedWithTheListensEpoch() {
        let observer = makeObserver()
        let sink = RecordingEventSink()
        XCTAssertNil(observer.onListen(withArguments: 7, eventSink: sink.sink))
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].starts, 1)
        sources[0].deliver(wifiPath)
        sources[0].deliver(offlinePath)
        XCTAssertEqual(sink.values, ["7:wifi", "7:none"])
    }

    func testALargeEpochSurvives() {
        let observer = makeObserver()
        let sink = RecordingEventSink()
        _ = observer.onListen(withArguments: NSNumber(value: 5_000_000_000 as Int64), eventSink: sink.sink)
        sources[0].deliver(cellularPath)
        XCTAssertEqual(sink.values, ["5000000000:cellular"])
    }

    func testAListenWithoutAnIntegerEpochIsAStreamErrorAndStartsNothing() {
        // Sent on the stream rather than returned, because a returned error
        // reaches FlutterError.reportError and leaves the Dart stream silent
        let arguments: [Any?] = [nil, "7", NSNumber(value: 7.5), NSNumber(value: 7.0), NSNumber(value: true)]
        for argument in arguments {
            let observer = makeObserver()
            let sink = RecordingEventSink()
            XCTAssertNil(observer.onListen(withArguments: argument, eventSink: sink.sink))
            XCTAssertEqual(sink.errorCodes, [NetworkTypeObserver.invalidEpoch], "\(String(describing: argument))")
        }
        XCTAssertTrue(sources.isEmpty)
    }

    func testAnInvalidEpochReleasesTheListenItReplaced() {
        // Both platforms cancel before validating, so a relisten that turns out
        // invalid must still release what it replaced
        let observer = makeObserver()
        let first = RecordingEventSink()
        _ = observer.onListen(withArguments: 1, eventSink: first.sink)
        let second = RecordingEventSink()
        XCTAssertNil(observer.onListen(withArguments: "x", eventSink: second.sink))
        XCTAssertEqual(sources[0].cancels, 1)
        XCTAssertEqual(second.errorCodes, [NetworkTypeObserver.invalidEpoch])
        sources[0].deliver(wifiPath)
        XCTAssertTrue(first.events.isEmpty)
        XCTAssertTrue(second.values.isEmpty, "the invalid listen's error is the only event it should ever see")
    }

    func testAnUpdateAfterCancelIsNotDelivered() {
        // An iOS event sink stays callable after its listen is cancelled, so
        // the observer must drop this itself
        let observer = makeObserver()
        let sink = RecordingEventSink()
        _ = observer.onListen(withArguments: 1, eventSink: sink.sink)
        XCTAssertNil(observer.onCancel(withArguments: nil))
        sources[0].deliver(wifiPath)
        XCTAssertTrue(sink.events.isEmpty)
        XCTAssertEqual(sources[0].cancels, 1)
    }

    func testAnUpdateDeliveredWhileItsListenIsCancellingIsDropped() {
        // A source may deliver while it is being cancelled, when the listen is
        // still alive but no longer current, so only the identity check stops it
        let observer = makeObserver()
        let sink = RecordingEventSink()
        _ = observer.onListen(withArguments: 1, eventSink: sink.sink)
        sources[0].deliverOnCancel = wifiPath
        observer.cancel()
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testAnUpdateDeliveredWhileARelistenIsCancellingItIsDropped() {
        // The same in-flight-during-cancel scenario, reached through a relisten
        // rather than an explicit cancel
        let observer = makeObserver()
        let first = RecordingEventSink()
        let second = RecordingEventSink()
        _ = observer.onListen(withArguments: 1, eventSink: first.sink)
        sources[0].deliverOnCancel = wifiPath
        _ = observer.onListen(withArguments: 2, eventSink: second.sink)
        XCTAssertTrue(first.events.isEmpty)
    }

    func testCancelIsIdempotentWhateverTheOrder() {
        // A listen cancel and an engine detachment both cancel
        let observer = makeObserver()
        _ = observer.onListen(withArguments: 1, eventSink: RecordingEventSink().sink)
        _ = observer.onCancel(withArguments: nil)
        observer.cancel()
        XCTAssertEqual(sources[0].cancels, 1)

        let detachedFirst = makeObserver()
        _ = detachedFirst.onListen(withArguments: 1, eventSink: RecordingEventSink().sink)
        detachedFirst.cancel()
        _ = detachedFirst.onCancel(withArguments: nil)
        XCTAssertEqual(sources[1].cancels, 1)
    }

    func testAListenWhileListeningReplacesThePreviousOne() {
        // A Dart hot restart relistens without cancelling its subscription, so
        // the observer must not depend on a cancel arriving first
        let observer = makeObserver()
        let first = RecordingEventSink()
        let second = RecordingEventSink()
        _ = observer.onListen(withArguments: 1, eventSink: first.sink)
        _ = observer.onListen(withArguments: 2, eventSink: second.sink)
        XCTAssertEqual(sources[0].cancels, 1)
        sources[0].deliver(wifiPath)
        sources[1].deliver(cellularPath)
        XCTAssertTrue(first.events.isEmpty)
        XCTAssertEqual(second.values, ["2:cellular"])
    }

    func testRelistenStartsAFreshMonitor() {
        // A cancelled NWPathMonitor cannot be restarted
        let observer = makeObserver()
        _ = observer.onListen(withArguments: 1, eventSink: RecordingEventSink().sink)
        _ = observer.onCancel(withArguments: nil)
        let sink = RecordingEventSink()
        _ = observer.onListen(withArguments: 2, eventSink: sink.sink)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.map(\.starts), [1, 1])
        sources[1].deliver(wifiPath)
        XCTAssertEqual(sink.values, ["2:wifi"])
    }

    func testCancellingOneObserverLeavesAnotherObserving() {
        // One observer per engine. Two instances against fakes, not two real
        // engines
        let first = makeObserver()
        let second = makeObserver()
        let sink = RecordingEventSink()
        _ = first.onListen(withArguments: 1, eventSink: RecordingEventSink().sink)
        _ = second.onListen(withArguments: 2, eventSink: sink.sink)
        first.cancel()
        sources[1].deliver(wifiPath)
        XCTAssertEqual(sink.values, ["2:wifi"])
        XCTAssertEqual(sources[1].cancels, 0)
    }

    func testTheMonitorDoesNotRetainTheObserver() {
        var observer: NetworkTypeObserver? = makeObserver()
        weak var weakObserver = observer
        _ = observer?.onListen(withArguments: 1, eventSink: RecordingEventSink().sink)
        observer = nil
        XCTAssertNil(weakObserver, "the monitor's handler holds the observer strongly")
    }

    func testReleasingTheObserverReleasesTheSourceEvenWhileListening() {
        // A strong capture of the listen in the update handler would form a
        // cycle through the source and the handler that only cancel() breaks.
        // Nothing here calls cancel, so releasing the observer must be enough
        var capturedSource: FakePathSource? = FakePathSource()
        weak var weakSource = capturedSource
        var observer: NetworkTypeObserver? = NetworkTypeObserver(makeSource: { capturedSource! })
        _ = observer?.onListen(withArguments: 1, eventSink: RecordingEventSink().sink)
        capturedSource = nil
        observer = nil
        XCTAssertNil(weakSource, "the update handler retained the source")
    }
}

/// Records the handlers channels install and the messages sent through it, so a
/// test drives the event channel's own listen protocol. The Objective-C header
/// FlutterBinaryMessenger.h is the authority on these signatures
final class RecordingMessenger: NSObject, FlutterBinaryMessenger {
    private(set) var handlers: [String: FlutterBinaryMessageHandler] = [:]
    private(set) var sent: [(channel: String, message: Data?)] = []

    func send(onChannel channel: String, message: Data?) {
        sent.append((channel, message))
    }

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        sent.append((channel, message))
    }

    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection {
        handlers[channel] = handler
        return 0
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

final class PluginRegistrationTests: XCTestCase {
    func testRegistrationPublishesTheInstanceAndServesTheNetworkChannel() throws {
        let source = FakePathSource()
        let plugin = CoproductHostContextPlugin(
            defaultsFilePath: nil,
            sessionProcess: SessionProcessState(),
            networkObserver: NetworkTypeObserver(makeSource: { source })
        )
        let messenger = RecordingMessenger()
        var delegates: [CoproductHostContextPlugin] = []
        var published: [NSObject] = []
        CoproductHostContextPlugin.install(
            plugin,
            messenger: messenger,
            addMethodCallDelegate: { delegate, _ in delegates.append(delegate) },
            publish: { published.append($0) }
        )
        // detachFromEngine(for:) reaches only a published instance
        XCTAssertEqual(published.count, 1)
        XCTAssertTrue(published.first === plugin)
        XCTAssertEqual(delegates.count, 1)
        XCTAssertTrue(delegates.first === plugin)

        // Through the event channel's own protocol, so the wiring is proven and
        // not only the observer
        let channel = "app.coproduct.flutter/network_type"
        let codec = FlutterStandardMethodCodec.sharedInstance()
        let handler = try XCTUnwrap(messenger.handlers[channel])
        handler(codec.encode(FlutterMethodCall(methodName: "listen", arguments: 4))) { _ in }
        source.deliver(wifiPath)
        let message = try XCTUnwrap(messenger.sent.last(where: { $0.channel == channel })?.message)
        XCTAssertEqual(decoded(codec.decodeEnvelope(message)), "4:wifi")
    }

    func testDetachCancelsTheNetworkObserver() {
        // Objective-C treats detachFromEngine(for:) as an optional protocol
        // method, so a Swift signature that does not match it exactly still
        // compiles and is silently never called by the engine
        XCTAssertTrue(
            CoproductHostContextPlugin().responds(to: Selector(("detachFromEngineForRegistrar:"))))

        let source = FakePathSource()
        let plugin = CoproductHostContextPlugin(
            defaultsFilePath: nil,
            sessionProcess: SessionProcessState(),
            networkObserver: NetworkTypeObserver(makeSource: { source })
        )
        let messenger = RecordingMessenger()
        CoproductHostContextPlugin.install(
            plugin,
            messenger: messenger,
            addMethodCallDelegate: { _, _ in },
            publish: { _ in }
        )
        let channel = "app.coproduct.flutter/network_type"
        let codec = FlutterStandardMethodCodec.sharedInstance()
        messenger.handlers[channel]?(codec.encode(FlutterMethodCall(methodName: "listen", arguments: 1))) { _ in }

        plugin.detach()

        XCTAssertEqual(source.cancels, 1)
    }
}
