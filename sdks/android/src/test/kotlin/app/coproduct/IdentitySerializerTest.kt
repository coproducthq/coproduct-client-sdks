package app.coproduct

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class IdentitySerializerTest {
    @Test
    fun appliesOperationsInCallOrder() = runTest {
        val serializer = IdentitySerializer(scope = this)
        val applied = CopyOnWriteArrayList<Int>()

        serializer.enqueue { delay(20); applied.add(1) }
        serializer.enqueue { applied.add(2) }
        serializer.enqueue { applied.add(3) }
        serializer.drain()

        assertEquals(listOf(1, 2, 3), applied)
    }

    @Test
    fun enqueueReturnsImmediatelyWithoutWaitingForTheOperation() = runTest {
        val serializer = IdentitySerializer(scope = this)
        var ran = false
        serializer.enqueue { delay(10_000); ran = true }
        assertEquals(false, ran)
    }

    /**
     * A failing operation must not poison the chain: later-enqueued operations
     * still run, and `drain()` itself must not throw. This also exercises the
     * internal `Log.e` call on the failure path -- under plain `testDebugUnitTest`
     * (no Robolectric, no `returnDefaultValues`), `android.util.Log.e` is
     * unmocked and throws `RuntimeException: Method e in android.util.Log not
     * mocked`. If the catch-and-log sequence didn't guard against that, this
     * test would fail with that exception instead of passing.
     */
    @Test
    fun operationFailureDoesNotPoisonLaterOperations() = runTest {
        val serializer = IdentitySerializer(scope = this)
        val applied = CopyOnWriteArrayList<Int>()

        serializer.enqueue { applied.add(1) }
        serializer.enqueue { throw RuntimeException("boom") }
        serializer.enqueue { applied.add(3) }
        serializer.drain()

        assertEquals(listOf(1, 3), applied)
    }

    /**
     * Exercises `enqueue` under genuine multi-threaded concurrency (a real
     * `Dispatchers.Default`-backed scope, not a cooperative single-threaded test
     * dispatcher, and no external lock serializing the `enqueue` calls
     * themselves) to demonstrate the internal `synchronized(lock)` in `enqueue`
     * actually protects `tail` from being raced on. Independent OS threads call
     * `serializer.enqueue` concurrently with no coordination between them, so
     * the cross-thread call order is genuinely non-deterministic -- this test
     * does not assert any particular order. Instead it asserts the
     * order-independent invariant the internal lock exists to guarantee: every
     * one of the `callCount` enqueued operations actually ran exactly once,
     * meaning no operation's link into the `tail` chain was ever dropped or
     * overwritten by a racing thread. If the internal lock were deleted, this
     * test would be expected to fail (or flake) by losing or duplicating
     * entries.
     */
    @Test
    fun concurrentEnqueueFromMultipleThreadsNeverLosesOrDuplicatesOperations() {
        val scope = CoroutineScope(Dispatchers.Default)
        val serializer = IdentitySerializer(scope = scope)
        val applied = CopyOnWriteArrayList<Int>()
        val callCount = 40
        val latch = CountDownLatch(callCount)

        // Each thread calls `enqueue` directly with no external lock around the
        // call itself, so threads genuinely race on IdentitySerializer's
        // internal `synchronized(lock)`.
        val threads = (0 until callCount).map { id ->
            Thread {
                serializer.enqueue { applied.add(id) }
                latch.countDown()
            }
        }

        threads.forEach { it.start() }
        assertEquals(true, latch.await(10, TimeUnit.SECONDS))
        threads.forEach { it.join(10_000) }

        runBlocking { serializer.drain() }

        assertEquals(callCount, applied.size)
        assertEquals((0 until callCount).toSet(), applied.toSet())
    }
}
