package app.coproduct

import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.HttpResponse

// Validation transport used by the current convenience initializer. The public
// initializer shape below shows where host transport injection will connect.
object MockTransport {
    var requestCount: Int = 0
        private set
    var completedHandshake: Boolean = false
        private set

    fun reset() {
        requestCount = 0
        completedHandshake = false
    }

    suspend fun request(): HttpResponse {
        requestCount += 1
        completedHandshake = true
        return HttpResponse(
            status = 200u,
            body = "{}".encodeToByteArray(),
            headers = emptyList(),
        )
    }
}

// Validation secure store used by the current convenience initializer.
object MockSecureStore {
    var readCount: Int = 0
        private set
    var writeCount: Int = 0
        private set
    var completedHandshake: Boolean = false
        private set

    private val values = mutableMapOf<String, String>()

    fun reset() {
        readCount = 0
        writeCount = 0
        completedHandshake = false
        values.clear()
    }

    suspend fun read(key: String): String? {
        readCount += 1
        completedHandshake = true
        return values[key]
    }

    suspend fun write(key: String, value: String) {
        writeCount += 1
        completedHandshake = true
        values[key] = value
    }
}

// Kotlin's top-level `private` is file-private, not package-private, so these
// must be `internal` (not `private`) to remain resolvable from Coproduct.kt's
// initialize() after this relocation.
internal object AndroidHostTransport : HostTransport {
    override suspend fun request(req: uniffi.coproduct_ffi_uniffi.HttpRequest): HttpResponse {
        return MockTransport.request()
    }
}

internal object AndroidHostSecureStore : HostSecureStore {
    override suspend fun read(key: String): String? {
        return MockSecureStore.read(key)
    }

    override suspend fun write(key: String, value: String) {
        MockSecureStore.write(key, value)
    }
}
