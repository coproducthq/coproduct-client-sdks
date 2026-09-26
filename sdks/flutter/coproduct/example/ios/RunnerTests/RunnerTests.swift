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
