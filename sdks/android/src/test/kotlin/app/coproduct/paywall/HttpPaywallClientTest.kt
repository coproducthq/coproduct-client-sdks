package app.coproduct.paywall

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

class HttpPaywallClientTest {
    private lateinit var server: HttpServer
    private var baseUrl: String = ""

    @Before
    fun setUp() {
        server = HttpServer.create(InetSocketAddress(0), 0)
        server.start()
        baseUrl = "http://localhost:${server.address.port}"
    }

    @After
    fun tearDown() {
        server.stop(0)
    }

    @Test
    fun `fetchPaywall returns null on a 404`() = runTest {
        server.createContext("/v1/paywalls/missing") { exchange ->
            exchange.sendResponseHeaders(404, -1)
            exchange.close()
        }
        val client = HttpPaywallClient(sdkKey = "cpk_test", edgeBaseUrl = baseUrl)

        assertNull(client.fetchPaywall("missing"))
    }

    @Test
    fun `fetchPaywall parses a successful response's nested paywall field`() = runTest {
        server.createContext("/v1/paywalls/p-1") { exchange ->
            val body = """{"paywall":{"paywallId":"p-1","version":1,"templateType":"hero_single_offer","content":{"offeringKey":"default","ctas":[],"html":"<div/>"},"packages":{},"html":"<div/>"}}"""
                .toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        val client = HttpPaywallClient(sdkKey = "cpk_test", edgeBaseUrl = baseUrl)

        val snapshot = client.fetchPaywall("p-1")

        assertEquals("p-1", snapshot?.paywallId)
    }

    @Test
    fun `recordPurchase posts the expected body and parses entitlements`() = runTest {
        server.createContext("/v1/purchases") { exchange ->
            val body = """{"appUserId":"u-1","entitlements":[{"entitlementId":"premium","isActive":true,"expiresAt":null,"willRenew":false,"source":"PURCHASE"}]}"""
                .toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        val client = HttpPaywallClient(sdkKey = "cpk_test", apiBaseUrl = baseUrl)

        val entitlements = client.recordPurchase(
            appUserId = "u-1",
            platform = "ANDROID",
            storeProductId = "premium_monthly",
            storeTransactionId = "tx-1",
            purchaseDateIso = "2026-10-19T00:00:00.000Z",
            expiresDateIso = null,
        )

        assertEquals(1, entitlements.size)
        assertEquals("premium", entitlements[0].entitlementId)
    }

    @Test
    fun `recordPurchase throws PaywallServerError with the server's error code on a non-2xx response`() = runTest {
        server.createContext("/v1/purchases") { exchange ->
            val body = """{"error":"Unknown product for this platform.","code":"unknown_product"}""".toByteArray()
            exchange.sendResponseHeaders(404, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        val client = HttpPaywallClient(sdkKey = "cpk_test", apiBaseUrl = baseUrl)

        val error = assertThrows(PaywallServerError::class.java) {
            kotlinx.coroutines.runBlocking {
                client.recordPurchase(
                    appUserId = "u-1",
                    platform = "ANDROID",
                    storeProductId = "unknown",
                    storeTransactionId = "tx-1",
                    purchaseDateIso = "2026-10-19T00:00:00.000Z",
                    expiresDateIso = null,
                )
            }
        }
        assertEquals(404, error.statusCode)
        assertEquals("unknown_product", error.code)
    }
}
