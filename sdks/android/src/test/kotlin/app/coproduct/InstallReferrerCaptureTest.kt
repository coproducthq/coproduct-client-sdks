package app.coproduct

import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A scripted [ReferrerSource] that calls back synchronously with [result],
 * or throws from [fetch] itself when [shouldThrow] is set, standing in for
 * the real client failing before it ever reaches the setup-finished callback
 */
private class FakeReferrerSource(
    private val result: String?,
    private val shouldThrow: Boolean = false,
) : ReferrerSource {
    var fetchCalls = 0

    override fun fetch(onResult: (String?) -> Unit) {
        fetchCalls++
        if (shouldThrow) throw IllegalStateException("referrer client crashed")
        onResult(result)
    }
}

/** A trivial in-memory [UtmStorage] so this file does not depend on UtmStoreTest's private fake */
private class FakeUtmStorage : UtmStorage {
    private var first: Map<String, String> = emptyMap()
    private var last: Map<String, String> = emptyMap()

    override fun readFirstTouch(): Map<String, String> = first

    override fun readLastTouch(): Map<String, String> = last

    override fun write(firstTouch: Map<String, String>, lastTouch: Map<String, String>): Boolean {
        first = firstTouch
        last = lastTouch
        return true
    }
}

/**
 * A minimal stand-in for the generated `parseUtmParameters`: splits a query
 * string on `&` and `=` and keeps only the `utm_`-prefixed keys, which is
 * enough to prove InstallReferrerCapture wires a referrer string into
 * UtmStore correctly without loading the native parser
 */
private fun fakeParse(query: String): Map<String, String> =
    query
        .removePrefix("?")
        .split("&")
        .filter { it.isNotEmpty() }
        .mapNotNull { pair ->
            val parts = pair.split("=", limit = 2)
            val key = parts[0]
            if (!key.startsWith("utm_")) null else key to parts.getOrElse(1) { "" }
        }
        .toMap()

class InstallReferrerCaptureTest {
    private fun captureWith(
        scope: TestScope,
        source: ReferrerSource,
        published: MutableList<Map<String, AttributeValue>>,
        errors: MutableList<Throwable> = mutableListOf(),
    ): InstallReferrerCapture =
        InstallReferrerCapture(
            source = source,
            store = UtmStore(FakeUtmStorage(), ::fakeParse, logFailure = {}),
            scope = scope,
            publish = { published.add(it) },
            logFailure = { errors.add(it) },
        )

    @Test
    fun successfulReferrerCapturesUtmAndPublishes() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val published = mutableListOf<Map<String, AttributeValue>>()
            val capture = captureWith(scope, FakeReferrerSource("utm_source=google&utm_medium=cpc"), published)

            capture.run()
            scope.advanceUntilIdle()

            assertEquals(1, published.size)
            val attributes = published.single()
            assertEquals("google", (attributes["utm_source"] as AttributeValue.String).value)
            assertEquals("cpc", (attributes["utm_medium"] as AttributeValue.String).value)
        }

    @Test
    fun nullReferrerIsANoOp() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val published = mutableListOf<Map<String, AttributeValue>>()
            val capture = captureWith(scope, FakeReferrerSource(result = null), published)

            capture.run()
            scope.advanceUntilIdle()

            assertTrue(published.isEmpty())
        }

    @Test
    fun emptyReferrerIsANoOp() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val published = mutableListOf<Map<String, AttributeValue>>()
            val capture = captureWith(scope, FakeReferrerSource(result = ""), published)

            capture.run()
            scope.advanceUntilIdle()

            assertTrue(published.isEmpty())
        }

    @Test
    fun referrerWithNoUtmParametersPublishesNothing() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val published = mutableListOf<Map<String, AttributeValue>>()
            val capture = captureWith(scope, FakeReferrerSource("some_other_param=1"), published)

            capture.run()
            scope.advanceUntilIdle()

            assertTrue(published.isEmpty())
        }

    @Test
    fun aFetchFailureIsLoggedAndSwallowed() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val published = mutableListOf<Map<String, AttributeValue>>()
            val errors = mutableListOf<Throwable>()
            val capture =
                captureWith(
                    scope,
                    FakeReferrerSource(result = null, shouldThrow = true),
                    published,
                    errors,
                )

            capture.run()
            scope.advanceUntilIdle()

            assertTrue(published.isEmpty())
            assertEquals(1, errors.size)
        }
}
