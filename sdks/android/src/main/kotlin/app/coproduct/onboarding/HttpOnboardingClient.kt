package app.coproduct.onboarding

import app.coproduct.onboarding.models.OnboardingFlowGraph
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import okhttp3.OkHttpClient
import okhttp3.Request

// Fetches an onboarding flow's graph directly from the R2-backed content
// CDN, bypassing the edge-worker round trip. An optional alternative
// content source for a host's CoproductClient.fetchOnboardingFlow -- a host
// app's adapter can delegate to this class for that one method while still
// implementing flag resolution and sdk context itself, since this class
// knows nothing about either. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/http_onboarding_client.dart and
// sdks/react-native/coproduct/src/onboarding/httpOnboardingClient.ts.
class HttpOnboardingClient(
    private val envSlug: String,
    private val contentBaseUrl: String = "https://content.coproduct.app",
    private val httpClient: OkHttpClient = OkHttpClient(),
) {
    // GET {contentBaseUrl}/onboarding/{flowId}/{envSlug}/latest.json. Returns
    // null on any failure -- not deployed to this environment yet (404), a
    // transport failure, or an unparseable body -- matching the
    // CoproductClient contract's documented rule that a host adapter decides
    // the fallback, not this class.
    suspend fun fetchOnboardingFlow(flowId: String): OnboardingFlowGraph? = withContext(Dispatchers.IO) {
        val url = "$contentBaseUrl/onboarding/$flowId/$envSlug/latest.json"
        val response = try {
            httpClient.newCall(Request.Builder().url(url).build()).execute()
        } catch (e: Exception) {
            return@withContext null
        }
        response.use {
            if (!it.isSuccessful) return@withContext null
            val body = it.body?.string() ?: return@withContext null
            try {
                OnboardingFlowGraph.fromJson(Json.parseToJsonElement(body) as JsonObject)
            } catch (e: Exception) {
                null
            }
        }
    }
}
