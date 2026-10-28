package app.coproduct.paywall

import app.coproduct.paywall.models.PaywallContent
import app.coproduct.paywall.models.PaywallSnapshot
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

private fun snap(id: String) = PaywallSnapshot(
    paywallId = id,
    version = 1,
    templateType = "hero_single_offer",
    content = PaywallContent(offeringKey = "default", ctas = emptyList(), html = "<p/>"),
    packages = emptyMap(),
    html = "<p/>",
)

class SnapshotCacheTest {
    @Test
    fun `snapshotCacheKey includes env, defaulting to api`() {
        assertEquals("p1|production", snapshotCacheKey("p1", "production"))
        assertEquals("p1|api", snapshotCacheKey("p1", null))
    }

    @Test
    fun `cold miss blocks on fetch and stores the entry`() = runTest {
        val cache = SnapshotCache(now = { 1000 }, scope = this)
        var calls = 0
        val out = cache.resolve("p1|api") { calls++; snap("p1") }
        assertEquals("p1", out?.paywallId)
        assertEquals(1, calls)
    }

    @Test
    fun `cold miss propagates a thrown fetch error`() = runTest {
        val cache = SnapshotCache(now = { 1000 }, scope = this)
        try {
            cache.resolve("p1|api") { throw IllegalStateException("boom") }
            fail("expected the thrown fetch error to propagate")
        } catch (e: IllegalStateException) {
            assertEquals("boom", e.message)
        }
    }

    @Test
    fun `cold miss returning null stores nothing`() = runTest {
        val cache = SnapshotCache(now = { 1000 }, scope = this)
        assertNull(cache.resolve("p1|api") { null })
        var calls = 0
        // Still a cold miss on the next read: nothing was cached.
        cache.resolve("p1|api") { calls++; null }
        assertEquals(1, calls)
    }

    @Test
    fun `fresh hit serves cached immediately and revalidates in the background`() = runTest {
        var now = 1000L
        val cache = SnapshotCache(now = { now }, scope = this)
        cache.resolve("p1|api") { snap("v1") }

        now = 1000 + SNAPSHOT_TTL_MS - 1 // still fresh
        var second = 0
        val served = cache.resolve("p1|api") { second++; snap("v2") }
        assertEquals("v1", served?.paywallId) // served the cached one

        cache.awaitRevalidation("p1|api")
        assertEquals(1, second) // revalidate fired once

        val after = cache.resolve("p1|api") { snap("v3") }
        assertEquals("v2", after?.paywallId) // background refresh updated the entry
    }

    @Test
    fun `stale hit block-fetches and replaces the entry`() = runTest {
        var now = 1000L
        val cache = SnapshotCache(now = { now }, scope = this)
        cache.resolve("p1|api") { snap("v1") }
        now = 1000 + SNAPSHOT_TTL_MS // exactly at cap => stale
        val served = cache.resolve("p1|api") { snap("v2") }
        assertEquals("v2", served?.paywallId)
    }

    @Test
    fun `stale hit serves the stale snapshot when refetch fails`() = runTest {
        var now = 1000L
        val cache = SnapshotCache(now = { now }, scope = this)
        cache.resolve("p1|api") { snap("v1") }
        now = 1000 + SNAPSHOT_TTL_MS
        val served = cache.resolve("p1|api") { throw IllegalStateException("net") }
        assertEquals("v1", served?.paywallId) // no throw, stale served
    }

    @Test
    fun `dedups concurrent background revalidations`() = runTest {
        var now = 1000L
        val cache = SnapshotCache(now = { now }, scope = this)
        cache.resolve("p1|api") { snap("v1") }
        now = 1001 // fresh
        var calls = 0
        val fetchFn: SnapshotFetch = { calls++; snap("v2") }
        cache.resolve("p1|api", fetchFn)
        cache.resolve("p1|api", fetchFn)
        cache.awaitRevalidation("p1|api")
        assertEquals(1, calls) // second revalidate deduped
    }

    @Test
    fun `warm always fetches and stores`() = runTest {
        var now = 1000L
        val cache = SnapshotCache(now = { now }, scope = this)
        cache.resolve("p1|api") { snap("v1") }
        now = 1001 // fresh
        cache.warm("p1|api") { snap("v2") }
        val served = cache.resolve("p1|api") { snap("v3") }
        assertEquals("v2", served?.paywallId) // warm overwrote even while fresh
    }
}
