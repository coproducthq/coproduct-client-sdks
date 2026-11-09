package app.coproduct.paywall

import app.coproduct.paywall.models.Entitlement
import app.coproduct.paywall.models.PaywallSnapshot
import app.coproduct.paywall.models.parseEntitlement
import app.coproduct.paywall.models.parsePaywallSnapshot
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * HTTP-backed PaywallClient. Makes its own requests rather than reusing the
 * base SDK's internal transport, which has no public accessor for the SDK
 * key or a request client -- the same real constraint Flutter/RN document.
 * sdkKey is the same string the host app already passed to
 * Coproduct.initialize(sdkKey). Mirrors
 * sdks/flutter/coproduct/lib/src/paywall/http_paywall_client.dart and
 * sdks/react-native/coproduct/src/paywall/httpPaywallClient.ts.
 */
class HttpPaywallClient(
    private val sdkKey: String,
    private val envSlug: String? = null,
    private val edgeBaseUrl: String = "https://sdk.coproduct.app",
    private val apiBaseUrl: String = "https://api.coproduct.app",
    private val contentBaseUrl: String = "https://content.coproduct.app",
) : PaywallClient {

    override suspend fun fetchPaywall(paywallId: String): PaywallSnapshot? =
        if (envSlug != null) fetchFromContentCdn(paywallId, envSlug) else fetchFromApi(paywallId)

    private suspend fun fetchFromContentCdn(paywallId: String, envSlug: String): PaywallSnapshot? =
        withContext(Dispatchers.IO) {
            try {
                val connection = openConnection("$contentBaseUrl/paywalls/$paywallId/$envSlug/latest.json", "GET")
                if (connection.responseCode !in 200..299) return@withContext null
                parsePaywallSnapshot(JSONObject(connection.inputStream.bufferedReader().readText()))
            } catch (_: Exception) {
                null
            }
        }

    private suspend fun fetchFromApi(paywallId: String): PaywallSnapshot? = withContext(Dispatchers.IO) {
        val connection = openConnection("$edgeBaseUrl/v1/paywalls/$paywallId", "GET", withAuth = true)
        if (connection.responseCode == 404) return@withContext null
        throwIfError(connection)
        val body = JSONObject(connection.inputStream.bufferedReader().readText())
        parsePaywallSnapshot(body.getJSONObject("paywall"))
    }

    override suspend fun recordPurchase(
        appUserId: String,
        platform: String,
        storeProductId: String,
        storeTransactionId: String,
        purchaseDateIso: String,
        expiresDateIso: String?,
    ): List<Entitlement> = withContext(Dispatchers.IO) {
        val transaction = JSONObject().apply {
            put("store_transaction_id", storeTransactionId)
            put("purchase_date", purchaseDateIso)
            if (expiresDateIso != null) put("expires_date", expiresDateIso)
        }
        val requestBody = JSONObject().apply {
            put("app_user_id", appUserId)
            put("platform", platform)
            put("store_product_id", storeProductId)
            put("transaction", transaction)
        }
        val connection = openConnection("$apiBaseUrl/v1/purchases", "POST", withAuth = true, body = requestBody)
        throwIfError(connection)
        entitlementsFromBody(JSONObject(connection.inputStream.bufferedReader().readText()))
    }

    override suspend fun getEntitlements(appUserId: String): List<Entitlement> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(appUserId, "UTF-8")
        val connection = openConnection("$apiBaseUrl/v1/entitlements?appUserId=$encoded", "GET", withAuth = true)
        throwIfError(connection)
        entitlementsFromBody(JSONObject(connection.inputStream.bufferedReader().readText()))
    }

    override suspend fun identify(appUserId: String, targetingKey: String) = withContext(Dispatchers.IO) {
        val requestBody = JSONObject().apply {
            put("app_user_id", appUserId)
            put("targeting_key", targetingKey)
        }
        val connection = openConnection("$apiBaseUrl/v1/identify", "POST", withAuth = true, body = requestBody)
        throwIfError(connection)
        Unit
    }

    private fun entitlementsFromBody(body: JSONObject): List<Entitlement> {
        val array = body.getJSONArray("entitlements")
        return (0 until array.length()).map { parseEntitlement(array.getJSONObject(it)) }
    }

    private fun openConnection(
        url: String,
        method: String,
        withAuth: Boolean = false,
        body: JSONObject? = null,
    ): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = method
        if (withAuth) connection.setRequestProperty("Authorization", "Bearer $sdkKey")
        if (body != null) {
            connection.setRequestProperty("Content-Type", "application/json")
            connection.doOutput = true
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
        }
        return connection
    }

    private fun throwIfError(connection: HttpURLConnection) {
        if (connection.responseCode in 200..299) return
        val errorBody = connection.errorStream?.bufferedReader()?.readText()
        var code: String? = null
        var message = "Request failed with status ${connection.responseCode}"
        if (errorBody != null) {
            try {
                val json = JSONObject(errorBody)
                code = json.optString("code").takeIf { it.isNotEmpty() }
                message = json.optString("error").takeIf { it.isNotEmpty() } ?: message
            } catch (_: Exception) {
                // Non-JSON error body -- keep the generic message
            }
        }
        throw PaywallServerError(connection.responseCode, code, message)
    }
}
