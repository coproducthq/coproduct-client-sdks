// Compiled (not executed) to prove a Swift class can satisfy the HostTransport
// and HostSecureStore async traits exported by UniFFI. If this typechecks, the
// foreign-async wiring is correct

import Foundation

final class TestTransport: HostTransport {
    func request(req: HttpRequest) async throws -> HttpResponse {
        return HttpResponse(status: 200, body: Data(), headers: [])
    }
}

final class TestSecureStore: HostSecureStore {
    func read(key: String) async throws -> String? { return nil }
    func write(key: String, value: String) async throws { }
}

func proveForeignAsyncCompiles() async {
    let transport: any HostTransport = TestTransport()
    let store: any HostSecureStore = TestSecureStore()
    _ = transport
    _ = store
}
