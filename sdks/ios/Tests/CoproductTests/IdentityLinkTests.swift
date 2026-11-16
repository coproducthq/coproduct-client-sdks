import XCTest
@testable import Coproduct

// identify tells the server which user an install's anonymous id belongs to.
// The request is best-effort, so these tests assert both what is sent and that
// nothing about it can fail or repeat
final class IdentityLinkTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "l", count: 32)

    // Records every request the stub sees. The handler runs on a URL loading
    // thread, so the storage is lock-guarded
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [(url: String, auth: String?, body: [String: String])] = []

        func record(_ request: URLRequest) {
            let body = (try? JSONSerialization.jsonObject(with: Self.bodyData(from: request))) as? [String: String]
            lock.lock()
            defer { lock.unlock() }
            _requests.append((
                request.url?.absoluteString ?? "",
                request.value(forHTTPHeaderField: "Authorization"),
                body ?? [:]
            ))
        }

        var requests: [(url: String, auth: String?, body: [String: String])] {
            lock.lock()
            defer { lock.unlock() }
            return _requests
        }

        // URLProtocol receives a POST body as a stream rather than httpBody
        private static func bodyData(from request: URLRequest) -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
    }

    private let recorder = Recorder()

    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubJSONURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }

    private func makeLinker(anonymousId: String?) -> IdentityLinker {
        IdentityLinker(
            client: HttpPaywallClient(sdkKey: "cpk_mob_test", apiBaseUrl: "https://api.example.test", session: stubSession()),
            anonymousId: { anonymousId }
        )
    }

    private func respond(status: Int) {
        StubJSONURLProtocol.handler = { [recorder] request in
            recorder.record(request)
            return (status, Data())
        }
    }

    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        IdentityLinker.resetForTesting()
        respond(status: 200)
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        IdentityLinker.sessionOverrideForTesting = nil
        IdentityLinker.resetForTesting()
        StubJSONURLProtocol.handler = nil
    }

    // MARK: - Linker

    func testLinkPostsThePairWithTheSdkKey() async {
        await makeLinker(anonymousId: "anon-1").link(userId: "alice", linkAnonymous: true)?.value
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, "https://api.example.test/v1/identify")
        XCTAssertEqual(requests.first?.auth, "Bearer cpk_mob_test")
        XCTAssertEqual(requests.first?.body, ["app_user_id": "anon-1", "targeting_key": "alice"])
    }

    func testLinkDoesNotRepeatTheSamePair() async {
        let linker = makeLinker(anonymousId: "anon-1")
        await linker.link(userId: "alice", linkAnonymous: true)?.value
        XCTAssertNil(linker.link(userId: "alice", linkAnonymous: true))
        // A second linker stands in for a shutdown and re-initialize: the pair
        // is remembered for the process, not per instance
        XCTAssertNil(makeLinker(anonymousId: "anon-1").link(userId: "alice", linkAnonymous: true))
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testLinkSendsADifferentUser() async {
        let linker = makeLinker(anonymousId: "anon-1")
        await linker.link(userId: "alice", linkAnonymous: true)?.value
        await linker.link(userId: "bob", linkAnonymous: true)?.value
        XCTAssertEqual(recorder.requests.map(\.body["targeting_key"]), ["alice", "bob"])
    }

    func testLinkSkipsWhenTheAnonymousIdIsUnknown() {
        XCTAssertNil(makeLinker(anonymousId: nil).link(userId: "alice", linkAnonymous: true))
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testLinkSkipsWhenTheIdsAreEqual() {
        XCTAssertNil(makeLinker(anonymousId: "same").link(userId: "same", linkAnonymous: true))
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testLinkSkipsWhenLinkAnonymousIsFalse() {
        XCTAssertNil(makeLinker(anonymousId: "anon-1").link(userId: "alice", linkAnonymous: false))
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testAFailedLinkIsSwallowedAndCanBeRetried() async {
        respond(status: 500)
        let linker = makeLinker(anonymousId: "anon-1")
        // The task's failure type is Never: a failing POST has nowhere to throw
        await linker.link(userId: "alice", linkAnonymous: true)?.value
        respond(status: 200)
        await linker.link(userId: "alice", linkAnonymous: true)?.value
        XCTAssertEqual(recorder.requests.count, 2)
    }

    // MARK: - Through the public API

    private func initialize(anonymousId: String) async throws {
        IdentityLinker.sessionOverrideForTesting = stubSession()
        let config = CoproductConfig(
            startupTimeout: 1,
            anonymousId: anonymousId,
            transport: TestTransport(),
            secureStore: TestSecureStore(),
            apiBaseUrl: "https://api.example.test"
        )
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)
    }

    // The link runs on a detached task after the ordered identity queue, so
    // poll for it with a bound rather than sleeping a fixed time
    private func awaitRequests(_ count: Int, timeout: TimeInterval = 2.0) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, recorder.requests.count < count {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return recorder.requests.count
    }

    func testAnonymousIdIsNilBeforeInitialize() {
        XCTAssertNil(Coproduct.anonymousId)
    }

    func testAnonymousIdIsExposedAfterInitialize() async throws {
        try await initialize(anonymousId: "anon-public")
        XCTAssertEqual(Coproduct.anonymousId, "anon-public")
        await Coproduct.shutdown()
        XCTAssertNil(Coproduct.anonymousId)
    }

    func testIdentifyPostsThePairOnce() async throws {
        try await initialize(anonymousId: "anon-public")
        Coproduct.identify(userId: "alice")
        Coproduct.identify(userId: "alice")
        await IdentitySerializer.shared.drain()
        let count = await awaitRequests(1)
        XCTAssertEqual(count, 1)
        // Give a wrongly repeated request time to land before asserting on it
        try? await Task.sleep(nanoseconds: 100_000_000)
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, "https://api.example.test/v1/identify")
        XCTAssertEqual(requests.first?.auth, "Bearer \(Self.validKey)")
        XCTAssertEqual(requests.first?.body, ["app_user_id": "anon-public", "targeting_key": "alice"])
    }

    func testIdentifySkipsThePostWhenLinkAnonymousIsFalseOrIdsAreEqual() async throws {
        try await initialize(anonymousId: "anon-public")
        Coproduct.identify(userId: "alice", attributes: [:], linkAnonymous: false)
        Coproduct.identify(userId: "anon-public")
        await IdentitySerializer.shared.drain()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testAFailingPostDoesNotFailIdentify() async throws {
        respond(status: 500)
        try await initialize(anonymousId: "anon-public")
        Coproduct.identify(userId: "alice")
        await IdentitySerializer.shared.drain()
        let count = await awaitRequests(1)
        XCTAssertEqual(count, 1)
        // The local identify applied regardless of the server's answer
        XCTAssertEqual(Coproduct.previousAnonymousId, "anon-public")
    }
}
