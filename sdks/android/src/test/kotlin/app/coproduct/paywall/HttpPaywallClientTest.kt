package app.coproduct.paywall

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun `getEntitlements names an anonymous id in the header and an app id only in the query`() = runTest {
        val headers = mutableMapOf<String, String?>()
        server.createContext("/v1/entitlements") { exchange ->
            val id = exchange.requestURI.query.removePrefix("appUserId=")
            headers[id] = exchange.requestHeaders.getFirst("X-Coproduct-Anonymous-Id")
            val body = """{"entitlements":[]}""".toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        val client = HttpPaywallClient(sdkKey = "cpk_test", apiBaseUrl = baseUrl)

        client.getEntitlements("822e8c6b-2040-457c-95ca-c022d2edbbdf")
        client.getEntitlements("user-1")

        assertEquals("822e8c6b-2040-457c-95ca-c022d2edbbdf", headers["822e8c6b-2040-457c-95ca-c022d2edbbdf"])
        assertNull(headers["user-1"])
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
    fun `recordPurchaseWithProof sends purchase_token inside transaction when given`() = runTest {
        var requestBody: JSONObject? = null
        server.createContext("/v1/purchases") { exchange ->
            requestBody = JSONObject(exchange.requestBody.bufferedReader().readText())
            val body = """{"appUserId":"u-1","entitlements":[]}""".toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        val client = HttpPaywallClient(sdkKey = "cpk_test", apiBaseUrl = baseUrl)

        client.recordPurchaseWithProof(
            appUserId = "u-1",
            platform = "ANDROID",
            storeProductId = "premium_monthly",
            storeTransactionId = "tx-1",
            purchaseDateIso = "2026-10-19T00:00:00.000Z",
            expiresDateIso = null,
            purchaseToken = "token-1",
        )

        val transaction = requestBody!!.getJSONObject("transaction")
        assertEquals("token-1", transaction.getString("purchase_token"))
        assertEquals("tx-1", transaction.getString("store_transaction_id"))
        assertFalse(transaction.has("signed_transaction"))
    }

    @Test
    fun `recordPurchase and a proofless recordPurchaseWithProof send no proof fields`() = runTest {
        val transactions = mutableListOf<JSONObject>()
        server.createContext("/v1/purchases") { exchange ->
            transactions.add(
                JSONObject(exchange.requestBody.bufferedReader().readText()).getJSONObject("transaction")
            )
            val body = """{"appUserId":"u-1","entitlements":[]}""".toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        val client = HttpPaywallClient(sdkKey = "cpk_test", apiBaseUrl = baseUrl)

        client.recordPurchase("u-1", "ANDROID", "premium_monthly", "tx-1", "2026-10-19T00:00:00.000Z", null)
        client.recordPurchaseWithProof("u-1", "ANDROID", "premium_monthly", "tx-1", "2026-10-19T00:00:00.000Z", null)

        assertEquals(2, transactions.size)
        for (transaction in transactions) {
            assertFalse(transaction.has("purchase_token"))
            assertFalse(transaction.has("signed_transaction"))
        }
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
