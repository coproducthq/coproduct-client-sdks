import Foundation
import XCTest
@testable import Coproduct

// The wrapper supplies the User-Agent the core sends on every snapshot fetch.
// It must identify the platform as coproduct-ios/<version>, not the FFI crate
final class UserAgentTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    final class CapturingTransport: HostTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var headers: [HttpHeader] = []

        // Synchronous so the lock is never taken inside the async request body,
        // which Swift 6 language mode rejects
        private func capture(_ headers: [HttpHeader]) {
            lock.lock()
            defer { lock.unlock() }
            self.headers = headers
        }

        func request(req: HttpRequest) async throws -> HttpResponse {
            capture(req.headers)
            return HttpResponse(status: 200, body: Data(), headers: [])
        }

        var userAgent: String? {
            lock.lock()
            defer { lock.unlock() }
            return headers.first { $0.name.lowercased() == "user-agent" }?.value
        }
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testInitializeSendsPlatformUserAgent() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let transport = CapturingTransport()
        let config = CoproductConfig(
            startupTimeout: 2,
            transport: transport,
            secureStore: TestSecureStore()
        )
        // initialize waits for the first poll to resolve the provider, so by the
        // time it returns the transport has seen the snapshot request and its
        // headers
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)

        XCTAssertEqual(transport.userAgent, "coproduct-ios/0.0.1-dev")
    }
}
