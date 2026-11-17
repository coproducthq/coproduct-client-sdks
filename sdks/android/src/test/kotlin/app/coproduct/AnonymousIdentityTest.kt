package app.coproduct

import app.coproduct.paywall.HttpPaywallClient
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.SecureStoreException

private class FakeSecureStore(
    private val values: MutableMap<String, String> = mutableMapOf(),
    private val failWrites: Boolean = false,
) : HostSecureStore {
    override suspend fun read(key: String): String? = values[key]

    override suspend fun write(key: String, value: String) {
        if (failWrites) throw SecureStoreException.WriteFailed()
        values[key] = value
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class AnonymousIdentityTest {
    // --- AnonymousIdCapturingSecureStore ---

    @Test
    fun `anonymous id is null until the core touches its key`() = runTest {
        val store = AnonymousIdCapturingSecureStore(FakeSecureStore(mutableMapOf("other" to "x")))

        assertNull(store.read(ANONYMOUS_ID_STORAGE_KEY))
        assertEquals("x", store.read("other"))
        store.write("other", "y")

        assertNull(store.anonymousId)
    }

    @Test
    fun `anonymous id is captured from a store read`() = runTest {
        val store = AnonymousIdCapturingSecureStore(
            FakeSecureStore(mutableMapOf(ANONYMOUS_ID_STORAGE_KEY to "anon-stored")),
        )

        assertEquals("anon-stored", store.read(ANONYMOUS_ID_STORAGE_KEY))

        assertEquals("anon-stored", store.anonymousId)
    }

    @Test
    fun `anonymous id is captured from a store write`() = runTest {
        val delegate = FakeSecureStore()
        val store = AnonymousIdCapturingSecureStore(delegate)

        store.write(ANONYMOUS_ID_STORAGE_KEY, "anon-fresh")

        assertEquals("anon-fresh", store.anonymousId)
        assertEquals("anon-fresh", delegate.read(ANONYMOUS_ID_STORAGE_KEY))
    }

    @Test
    fun `anonymous id is captured from a write that fails`() {
        val store = AnonymousIdCapturingSecureStore(FakeSecureStore(failWrites = true))

        assertThrows(SecureStoreException.WriteFailed::class.java) {
            runBlocking { store.write(ANONYMOUS_ID_STORAGE_KEY, "anon-session") }
        }

        assertEquals("anon-session", store.anonymousId)
    }

    // --- IdentifyLinker ---

    @Test
    fun `identify posts the anonymous id and user id pair once`() = runTest {
        val posted = mutableListOf<Pair<String, String>>()
        val linker = IdentifyLinker(scope = this, anonymousId = { "anon-1" }) { anonymous, user ->
            posted.add(anonymous to user)
        }

        assertNotNull(linker.link("user-1", linkAnonymous = true))
        assertNull(linker.link("user-1", linkAnonymous = true))
        advanceUntilIdle()

        assertEquals(listOf("anon-1" to "user-1"), posted)
    }

    @Test
    fun `identify posts again for a different user`() = runTest {
        val posted = mutableListOf<Pair<String, String>>()
        val linker = IdentifyLinker(scope = this, anonymousId = { "anon-1" }) { anonymous, user ->
            posted.add(anonymous to user)
        }

        linker.link("user-1", linkAnonymous = true)
        linker.link("user-2", linkAnonymous = true)
        advanceUntilIdle()

        assertEquals(listOf("anon-1" to "user-1", "anon-1" to "user-2"), posted)
    }

    @Test
    fun `identify skips the post when the ids are equal, unknown, or linking is disabled`() = runTest {
        val posted = mutableListOf<Pair<String, String>>()
        val post: suspend (String, String) -> Unit = { anonymous, user -> posted.add(anonymous to user) }

        assertNull(IdentifyLinker(this, { "same" }, post).link("same", linkAnonymous = true))
        assertNull(IdentifyLinker(this, { null }, post).link("user-1", linkAnonymous = true))
        assertNull(IdentifyLinker(this, { "anon-1" }, post).link("user-1", linkAnonymous = false))
        advanceUntilIdle()

        assertEquals(emptyList<Pair<String, String>>(), posted)
    }

    @Test
    fun `a failing post does not fail identify and may be retried`() = runTest {
        // Drives the linker through the same serializer path
        // CoproductClient.identify uses, since NativeCoproductClient cannot
        // be faked (see CoproductClientTest).
        val applied = mutableListOf<String>()
        var attempts = 0
        val linker = IdentifyLinker(scope = this, anonymousId = { "anon-1" }) { _, _ ->
            attempts += 1
            throw IllegalStateException("offline")
        }
        val serializer = IdentitySerializer(scope = this)

        serializer.enqueue {
            applied.add("user-1")
            linker.link("user-1", linkAnonymous = true)
        }
        serializer.enqueue { applied.add("user-2") }
        serializer.drain()
        advanceUntilIdle()

        assertEquals(listOf("user-1", "user-2"), applied)
        assertEquals(1, attempts)

        linker.link("user-1", linkAnonymous = true)
        advanceUntilIdle()
        assertEquals(2, attempts)
    }

    @Test
    fun `the post reaches v1 identify with the sdk key and both ids`() = runBlocking {
        val server = HttpServer.create(InetSocketAddress(0), 0)
        var authorization: String? = null
        var body: JSONObject? = null
        server.createContext("/v1/identify") { exchange ->
            authorization = exchange.requestHeaders.getFirst("Authorization")
            body = JSONObject(exchange.requestBody.bufferedReader().readText())
            val response = "{}".toByteArray()
            exchange.sendResponseHeaders(200, response.size.toLong())
            exchange.responseBody.use { it.write(response) }
        }
        server.start()
        try {
            val client = HttpPaywallClient(sdkKey = "cpk_test", apiBaseUrl = "http://localhost:${server.address.port}")
            val linker = IdentifyLinker(scope = this, anonymousId = { "anon-1" }, post = client::identify)

            linker.link("user-1", linkAnonymous = true)!!.join()

            assertEquals("Bearer cpk_test", authorization)
            assertEquals("anon-1", body?.getString("anonymous_id"))
            assertEquals("user-1", body?.getString("targeting_key"))
        } finally {
            server.stop(0)
        }
    }
}
