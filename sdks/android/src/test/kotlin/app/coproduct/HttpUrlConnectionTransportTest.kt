package app.coproduct

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.MalformedURLException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.HttpHeader
import uniffi.coproduct_ffi_uniffi.HttpMethod
import uniffi.coproduct_ffi_uniffi.HttpRequest
import uniffi.coproduct_ffi_uniffi.TransportException

/**
 * A test double standing in for a live [HttpURLConnection]. Captures the
 * request the transport writes (method, headers, body, timeouts) and replays
 * a scripted response, or throws a scripted failure from [getResponseCode]
 * the way a real socket failure would
 */
private class FakeHttpURLConnection(
    url: URL,
    private val responseStatus: Int = 200,
    private val responseBody: ByteArray = ByteArray(0),
    private val responseHeaders: Map<String, List<String>> = emptyMap(),
    private val failure: Throwable? = null,
) : HttpURLConnection(url) {
    val sentHeaders = mutableMapOf<String, String>()
    val sentBody = ByteArrayOutputStream()

    override fun connect() {}

    override fun disconnect() {}

    override fun usingProxy(): Boolean = false

    override fun setRequestProperty(key: String, value: String) {
        sentHeaders[key] = value
    }

    override fun getOutputStream(): OutputStream = sentBody

    override fun getResponseCode(): Int {
        failure?.let { throw it }
        return responseStatus
    }

    override fun getInputStream(): InputStream = ByteArrayInputStream(responseBody)

    override fun getErrorStream(): InputStream = ByteArrayInputStream(responseBody)

    override fun getHeaderFields(): Map<String, List<String>> = responseHeaders
}

private class FakeOpener(
    private val onOpen: (String) -> HttpURLConnection,
) : HttpConnectionOpener {
    override fun open(url: String): HttpURLConnection = onOpen(url)
}

class HttpUrlConnectionTransportTest {
    @Test
    fun getEchoesMethodAndHeader() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            responseStatus = 200,
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        val response = transport.request(
            HttpRequest(
                method = HttpMethod.GET,
                url = "https://edge.example.com/v1/snapshot",
                headers = listOf(HttpHeader(name = "authorization", value = "Bearer cpk_test")),
                body = null,
            ),
        )

        assertEquals(200.toUShort(), response.status)
        assertEquals("GET", connection.requestMethod)
        assertEquals("Bearer cpk_test", connection.sentHeaders["authorization"])
        assertEquals(false, connection.doOutput)
    }

    @Test
    fun postEncodesMethodAndBody() = runTest {
        val connection = FakeHttpURLConnection(URL("https://edge.example.com/v1/snapshot"))
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })
        val body = "{\"k\":1}".encodeToByteArray()

        transport.request(
            HttpRequest(
                method = HttpMethod.POST,
                url = "https://edge.example.com/v1/snapshot",
                headers = emptyList(),
                body = body,
            ),
        )

        assertEquals("POST", connection.requestMethod)
        assertEquals(true, connection.doOutput)
        assertEquals(body.toList(), connection.sentBody.toByteArray().toList())
    }

    @Test
    fun responseBodyAndHeadersPassThroughVerbatim() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            responseStatus = 200,
            responseBody = "{\"ok\":true}".encodeToByteArray(),
            responseHeaders = mapOf("Content-Type" to listOf("application/json")),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        val response = transport.request(
            HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
        )

        assertEquals("{\"ok\":true}", response.body.decodeToString())
        val contentType = response.headers.firstOrNull { it.name == "Content-Type" }?.value
        assertEquals("application/json", contentType)
    }

    @Test
    fun errorStatusesPassThroughVerbatimRatherThanThrowing() = runTest {
        // The core interprets 401 and 5xx, so the transport must not map them
        // onto Unauthorized or ServerException itself
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            responseStatus = 401,
            responseBody = "unauthorized".encodeToByteArray(),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        val response = transport.request(
            HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
        )

        assertEquals(401.toUShort(), response.status)
        assertEquals("unauthorized", response.body.decodeToString())
    }

    @Test
    fun serverErrorStatusPassesThroughVerbatim() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            responseStatus = 500,
            responseBody = "boom".encodeToByteArray(),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        val response = transport.request(
            HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
        )

        assertEquals(500.toUShort(), response.status)
        assertEquals("boom", response.body.decodeToString())
    }

    @Test
    fun requestTimeoutOverrideIsAppliedToTheConnection() = runTest {
        val connection = FakeHttpURLConnection(URL("https://edge.example.com/v1/snapshot"))
        val transport = HttpUrlConnectionTransport(requestTimeoutMs = 5_000L, opener = FakeOpener { connection })

        transport.request(
            HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
        )

        assertEquals(5_000, connection.connectTimeout)
        assertEquals(5_000, connection.readTimeout)
    }

    @Test
    fun socketTimeoutMapsToTransportTimeout() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/never"),
            failure = SocketTimeoutException("timed out"),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/never", headers = emptyList(), body = null),
            )
            fail("expected a timeout")
        } catch (_error: TransportException.Timeout) {
            // expected
        }
    }

    @Test
    fun unknownHostMapsToNetworkUnreachable() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.invalid/v1/snapshot"),
            failure = UnknownHostException("edge.invalid"),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = "https://edge.invalid/v1/snapshot", headers = emptyList(), body = null),
            )
            fail("expected a network-unreachable error")
        } catch (_error: TransportException.NetworkUnreachable) {
            // expected
        }
    }

    @Test
    fun connectExceptionMapsToNetworkUnreachable() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            failure = ConnectException("refused"),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
            )
            fail("expected a network-unreachable error")
        } catch (_error: TransportException.NetworkUnreachable) {
            // expected
        }
    }

    @Test
    fun malformedUrlMapsToMalformedResponse() = runTest {
        val transport = HttpUrlConnectionTransport(
            opener = FakeOpener { throw MalformedURLException("no protocol: not a url") },
        )

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = "not a url", headers = emptyList(), body = null),
            )
            fail("expected a malformed-response error")
        } catch (_error: TransportException.MalformedResponse) {
            // expected
        }
    }

    @Test
    fun unparseableResponseCodeMapsToMalformedResponse() = runTest {
        // HttpURLConnection documents -1 as the response code when no HTTP
        // status line could be discerned
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            responseStatus = -1,
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
            )
            fail("expected a malformed-response error")
        } catch (_error: TransportException.MalformedResponse) {
            // expected
        }
    }

    @Test
    fun unexpectedIOExceptionMapsToOther() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            failure = IOException("disk full, somehow"),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
            )
            fail("expected an Other error")
        } catch (error: TransportException.Other) {
            assertTrue(error.reason.contains("disk full"))
        }
    }

    @Test
    fun unexpectedRuntimeExceptionMapsToOther() = runTest {
        val connection = FakeHttpURLConnection(
            URL("https://edge.example.com/v1/snapshot"),
            failure = RuntimeException("surprise"),
        )
        val transport = HttpUrlConnectionTransport(opener = FakeOpener { connection })

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = "https://edge.example.com/v1/snapshot", headers = emptyList(), body = null),
            )
            fail("expected an Other error")
        } catch (error: TransportException.Other) {
            assertTrue(error.reason.contains("surprise"))
        }
    }
}
