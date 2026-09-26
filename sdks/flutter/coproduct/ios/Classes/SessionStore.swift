import Foundation

/// Both session attributes from one transaction, never one without the other,
/// with first_seen_at in integer epoch seconds UTC and session_count from 1
struct SessionPair: Equatable {
    let firstSeenAt: Int64
    let sessionCount: Int64

    var channelValue: [String: NSNumber] {
        [
            "first_seen_at": NSNumber(value: firstSeenAt),
            "session_count": NSNumber(value: sessionCount),
        ]
    }
}

/// The seam the transaction is written against, so a test can drop a write or
/// make the store report something other than what was written. Neither method
/// throws because UserDefaults does not, which is why iOS has no counterpart to
/// Android's exception latch
protocol SessionStorage {
    /// False when the store cannot be trusted to read what it holds, in which
    /// case the transaction must not run at all
    var isAvailable: Bool { get }
    func read() -> Any?
    func write(_ record: [String: Any])
}

/// One record under one key. UserDefaults has no multi-key transaction, so two
/// keys could be split by a crash between writes and leave a timestamp with no
/// count. The key is Flutter-namespaced so it never shares a counter with the
/// native SDK, which would count one process twice
struct UserDefaultsSessionStorage: SessionStorage {
    static let key = "app.coproduct.flutter.session"

    let defaults: UserDefaults
    /// The file these defaults are kept in, or nil when it cannot be worked
    /// out, in which case only the defaults themselves are consulted
    let filePath: String?

    var isAvailable: Bool {
        DefaultsFile.canTrust(defaults, key: Self.key, filePath: filePath)
    }

    func read() -> Any? { defaults.object(forKey: Self.key) }

    func write(_ record: [String: Any]) { defaults.set(record, forKey: Self.key) }
}

/// Decides whether UserDefaults can be trusted to report what the session
/// record holds. Before the user first unlocks the device after boot, the file
/// the defaults live in is protected and they read as empty, which would look
/// like a first launch and could overwrite the real record. The device's lock
/// state is the wrong signal: with the default protection class the file stays
/// readable while locked once the device has been unlocked since boot, so a
/// background launch on a locked phone still counts. An app whose default
/// protection class is complete has a file that is unreadable whenever the
/// device is locked, so its locked launches omit the session, which is all that
/// file allows
enum DefaultsFile {
    static var standardPath: String? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSHomeDirectory() + "/Library/Preferences/\(bundleID).plist"
    }

    /// A missing file has nothing to overwrite, and an unknown path counts as
    /// available
    static func isReadable(atPath path: String?) -> Bool {
        guard let path else { return true }
        // errno is read inside the closure, before anything else can change it
        return path.withCString { cPath in
            let descriptor = open(cPath, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
            return errno == ENOENT
        }
    }

    /// What the file holds for one key
    enum Lookup: Equatable {
        case missing
        case unreadable
        case holdsKey
        case lacksKey
    }

    /// Decides from a single open, so the file cannot become unreadable between
    /// being checked and being read. A file that opens but does not parse holds
    /// no record anyone could read back, so it lacks the key rather than
    /// locking the store out for good
    static func lookup(_ key: String, atPath path: String) -> Lookup {
        // errno is read inside the closure, before anything else can change it
        let opened: (descriptor: Int32, error: Int32) = path.withCString { cPath in
            let descriptor = open(cPath, O_RDONLY)
            return (descriptor, descriptor < 0 ? errno : 0)
        }
        guard opened.descriptor >= 0 else {
            return opened.error == ENOENT ? .missing : .unreadable
        }
        let handle = FileHandle(fileDescriptor: opened.descriptor, closeOnDealloc: true)
        // An empty file reads as nil, which is a file with no record, while a
        // read that throws means the file cannot be read after all
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            return .unreadable
        }
        guard let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil) as? [String: Any]
        else { return .lacksKey }
        return plist[key] == nil ? .lacksKey : .holdsKey
    }

    /// When the defaults report no record, the file must not hold one either.
    /// On some iOS releases a process that read its defaults before first
    /// unlock keeps that empty copy after the file becomes readable, while a
    /// true first launch has no record in the file. An app that removes the
    /// record shortly before initializing also trips this until the file
    /// catches up, which omits the session for that one process rather than
    /// risking a wrong count
    static func canTrust(_ defaults: UserDefaults, key: String, filePath: String?) -> Bool {
        guard let filePath else { return true }
        guard defaults.object(forKey: key) == nil else {
            // Nothing can be overwritten, but a file that cannot be read now
            // would not keep the increment either
            return isReadable(atPath: filePath)
        }
        switch lookup(key, atPath: filePath) {
        case .missing, .lacksKey: return true
        case .unreadable, .holdsKey: return false
        }
    }
}

/// What one OS process knows about its session: the pair it counted, or that a
/// write failed. Every plugin instance uses the shared state, so every
/// FlutterEngine in the process contends for one lock and receives one pair.
/// Tests build their own, one per simulated process. Sendable by hand because
/// the lock guards every mutable field, and those fields are private to this
/// file so nothing outside the store can reach them without it
final class SessionProcessState: @unchecked Sendable {
    static let shared = SessionProcessState()

    let lock = NSLock()
    fileprivate var pair: SessionPair?
    fileprivate var failed = false
}

/// Counts OS process lifetimes, once per process however many engines ask
final class SessionStore {
    static let firstSeenAtField = "firstSeenAt"
    static let sessionCountField = "sessionCount"

    /// The largest integer a double holds exactly. Both values reach the core as
    /// a double, so anything larger would publish a different number from the
    /// one stored
    static let maxExact: Int64 = 9_007_199_254_740_991

    let process: SessionProcessState
    private let storage: SessionStorage
    private let now: () -> Date

    init(
        storage: SessionStorage,
        process: SessionProcessState = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.storage = storage
        self.process = process
        self.now = now
    }

    /// Returns this process's pair, or nil when the read-back did not yield both
    /// values. UserDefaults acknowledges no write and throws nothing, so the
    /// read-back catches a rejected or malformed write and nothing more: it does
    /// not prove the record reached disk
    func begin() -> SessionPair? {
        process.lock.lock()
        defer { process.lock.unlock() }

        // A failure already seen in this process sticks, so a second engine
        // cannot publish values the process already knows it failed to keep
        if process.failed { return nil }
        // Counted already: every later caller gets the same pair without
        // touching the store, so a record cleared or corrupted since cannot
        // start a second transaction or hand two engines different values
        if let pair = process.pair { return pair }
        // A store that reads as empty only because it is locked would restart
        // the count and could overwrite the real record, so nothing is read or
        // written and the failure sticks like any other
        guard storage.isAvailable else {
            process.failed = true
            return nil
        }
        let stored = Self.validate(storage.read(), maxCount: Self.maxExact - 1)
        let firstSeenAt = stored?.firstSeenAt ?? Int64(now().timeIntervalSince1970)
        let sessionCount = (stored?.sessionCount ?? 0) + 1
        storage.write([
            Self.firstSeenAtField: NSNumber(value: firstSeenAt),
            Self.sessionCountField: NSNumber(value: sessionCount),
        ])
        // What the store reports holding, not what this method meant to write.
        // Never retried in this process, so a failure can cost an omission but
        // never a second increment
        guard let confirmed = Self.validate(storage.read(), maxCount: Self.maxExact) else {
            process.failed = true
            return nil
        }
        process.pair = confirmed
        return confirmed
    }

    /// A missing, wrong-typed, fractional, negative, zero-count, or out-of-range
    /// value means the record is corrupt, and a corrupt record restarts rather
    /// than publishing a nonsensical cohort value. A stored count must leave room
    /// for the increment, so it is read with a tighter upper bound than the
    /// confirmed record is. Looser than Android about the number's storage type
    /// because a plist number does not keep one
    private static func validate(_ raw: Any?, maxCount: Int64) -> SessionPair? {
        guard let record = raw as? [String: Any],
              let firstSeenAt = integer(record[firstSeenAtField]),
              let sessionCount = integer(record[sessionCountField]),
              (0...maxExact).contains(firstSeenAt),
              (1...maxCount).contains(sessionCount)
        else { return nil }
        return SessionPair(firstSeenAt: firstSeenAt, sessionCount: sessionCount)
    }

    /// A whole number that is not a boolean. NSNumber bridges true to 1, so the
    /// type check is what keeps a stored flag from reading as a count. The
    /// round trip through Double rejects a fraction, NaN, and infinity
    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let whole = number.int64Value
        guard Double(whole) == number.doubleValue else { return nil }
        return whole
    }
}
