import XCTest
@testable import Coproduct

// The host owns the polling schedule. With pollOnForeground enabled, returning
// to the foreground re-polls immediately rather than waiting for the next
// interval tick. With it disabled, the foreground notification is ignored and
// only the interval timer drives polling. A long interval keeps the scheduled
// tick out of the test window so the only request a foreground post can add is
// the foreground fast path itself. The recorder counts transport requests, and
// initialize awaits a first poll, so a baseline is taken after init to isolate
// the foreground-driven request
final class PollOnForegroundTests: XCTestCase {
    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    private func validKey(body letter: Character) -> String {
        "cpk_mob_" + String(repeating: letter, count: 32)
    }

    func testForegroundTriggersImmediatePollWhenEnabled() async throws {
        let recorder = RecordingTransport()
        try await Coproduct.initialize(
            sdkKey: validKey(body: "a"),
            config: CoproductConfig(
                pollInterval: 60,
                startupTimeout: 1,
                transport: recorder,
                secureStore: TestSecureStore(),
                pollOnForeground: true
            )
        )
        let baseline = await recorder.count()
        NotificationCenter.default.post(name: HostTimer.didBecomeActiveNotification, object: nil)
        try await waitForCount(recorder, toExceed: baseline)
        let after = await recorder.count()
        XCTAssertGreaterThan(after, baseline)
    }

    func testForegroundDoesNotPollWhenDisabled() async throws {
        let recorder = RecordingTransport()
        try await Coproduct.initialize(
            sdkKey: validKey(body: "b"),
            config: CoproductConfig(
                pollInterval: 60,
                startupTimeout: 1,
                transport: recorder,
                secureStore: TestSecureStore(),
                pollOnForeground: false
            )
        )
        let baseline = await recorder.count()
        NotificationCenter.default.post(name: HostTimer.didBecomeActiveNotification, object: nil)
        // Give any erroneously-installed observer ample time to fire. No
        // additional request should appear because the foreground observer is
        // not registered when pollOnForeground is false
        try await Task.sleep(nanoseconds: 300_000_000)
        let after = await recorder.count()
        XCTAssertEqual(after, baseline)
    }

    // Polls land on a background queue and traverse the FFI boundary, so the
    // request arrives slightly after the notification post. Poll until the
    // count grows rather than sleeping a fixed interval, with a ceiling so a
    // genuinely missing poll fails fast instead of hanging
    private func waitForCount(_ recorder: RecordingTransport, toExceed baseline: Int) async throws {
        for _ in 0..<50 {
            if await recorder.count() > baseline { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

actor RecordingTransport: HostTransport {
    private var calls = 0
    func count() -> Int { calls }
    func request(req _: HttpRequest) async throws -> HttpResponse {
        calls += 1
        // A valid snapshot so the poll succeeds and the provider stays in normal
        // cadence. A failing poll would open a back-off window that the foreground
        // fast path deliberately waits out, which is a separate contract
        let body = """
        {"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",\
        "environment":{"slug":"e","projectKey":"p"},"flags":[],"segments":[]},\
        "sdkContext":{"timezone":"UTC"}}
        """
        return HttpResponse(status: 200, body: Data(body.utf8), headers: [HttpHeader(name: "ETag", value: "v1")])
    }
}
