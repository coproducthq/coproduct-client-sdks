package app.coproduct.onboarding

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class HttpOnboardingClientTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun clientFor(server: MockWebServer) =
        HttpOnboardingClient(envSlug = "prod", contentBaseUrl = server.url("/").toString().trimEnd('/'))

    @Test
    fun fetchesAndParsesAFlowGraph() = runBlocking {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"startScreenId":"welcome","screens":[{"id":"welcome","html":"<p>Hi</p>","transitions":[],"defaultNext":{"type":"complete"}}]}"""
            )
        )
        val graph = clientFor(server).fetchOnboardingFlow("flow1")
        assertEquals("welcome", graph?.startScreenId)

        val request = server.takeRequest()
        assertEquals("/onboarding/flow1/prod/latest.json", request.path)
    }

    @Test
    fun returnsNullOnA404() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(404))
        assertNull(clientFor(server).fetchOnboardingFlow("missing"))
    }

    @Test
    fun returnsNullOnAnUnparseableBody() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("not json"))
        assertNull(clientFor(server).fetchOnboardingFlow("flow1"))
    }
}
