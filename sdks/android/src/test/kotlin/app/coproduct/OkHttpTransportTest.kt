package app.coproduct

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.HttpHeader
import uniffi.coproduct_ffi_uniffi.HttpMethod
import uniffi.coproduct_ffi_uniffi.HttpRequest
import uniffi.coproduct_ffi_uniffi.TransportException
import java.net.SocketTimeoutException

class OkHttpTransportTest {
    private lateinit var server: MockWebServer

    @Before
    fun startServer() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun stopServer() {
        server.shutdown()
    }

    @Test
    fun getRequestReturnsStatusBodyAndHeaders() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("{\"ok\":true}").addHeader("X-Test", "1"))
        val transport = OkHttpTransport()

        val response = transport.request(
            HttpRequest(method = HttpMethod.GET, url = server.url("/flags").toString(), headers = emptyList(), body = null),
        )

        assertEquals(200, response.status.toInt())
        assertEquals("{\"ok\":true}", response.body.toString(Charsets.UTF_8))
        assertEquals("1", response.headers.first { it.name == "X-Test" }.value)
    }

    @Test
    fun postRequestSendsHeadersAndBody() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(201).setBody(""))
        val transport = OkHttpTransport()

        transport.request(
            HttpRequest(
                method = HttpMethod.POST,
                url = server.url("/events").toString(),
                headers = listOf(HttpHeader("X-Key", "abc")),
                body = "{\"n\":1}".toByteArray(),
            ),
        )

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("abc", recorded.getHeader("X-Key"))
        assertEquals("{\"n\":1}", recorded.body.readUtf8())
    }

    @Test
    fun aTimeoutMapsToTransportExceptionTimeout() = runBlocking {
        // Use a custom dispatcher that sleeps before responding
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                Thread.sleep(200)  // Sleep well past the 50ms timeout below
                return MockResponse().setResponseCode(200).setBody("delayed")
            }
        }

        val transport = OkHttpTransport(requestTimeoutMillis = 50)

        try {
            transport.request(
                HttpRequest(method = HttpMethod.GET, url = server.url("/slow").toString(), headers = emptyList(), body = null),
            )
            org.junit.Assert.fail("expected TransportException.Timeout")
        } catch (error: TransportException.Timeout) {
            // expected
        }
    }
}
