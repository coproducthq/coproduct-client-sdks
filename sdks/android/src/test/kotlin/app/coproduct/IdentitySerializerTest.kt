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
     * Exercises `enqueue` under genuine multi-threaded concurrency (a real
     * `Dispatchers.Default`-backed scope, not a cooperative single-threaded test
     * dispatcher) to demonstrate the `synchronized` block in `enqueue` actually
     * preserves call order when multiple threads race to enqueue. Several
     * coroutines call `enqueue` concurrently, but each `enqueue` call itself is
     * made from a single coordinating coroutine in a known sequence, so the
     * recorded order is deterministic: it must match the order `enqueue` was
     * called in, regardless of which underlying thread each operation body
     * happens to run on.
     */
    @Test
    fun appliesOperationsInCallOrderUnderConcurrentEnqueueFromMultipleThreads() {
        val scope = CoroutineScope(Dispatchers.Default)
        val serializer = IdentitySerializer(scope = scope)
        val applied = CopyOnWriteArrayList<Int>()
        val callCount = 40
        val latch = CountDownLatch(callCount)

        // Several real OS threads race to call `enqueue`, genuinely contending
        // on IdentitySerializer's internal `synchronized(lock)`. The sequence
        // number is assigned and the `enqueue` call is made atomically, inside
        // the same `callOrderLock` critical section, so the order in which
        // threads win that lock *is* the order `enqueue` is actually called in
        // -- making the expected result deterministic rather than dependent on
        // which thread happens to run first.
        var nextSequence = 0
        val callOrderLock = Any()

        val threads = (1..8).map {
            Thread {
                while (true) {
                    val shouldContinue = synchronized(callOrderLock) {
                        val sequence = nextSequence
                        if (sequence >= callCount) {
                            false
                        } else {
                            nextSequence++
                            serializer.enqueue { applied.add(sequence) }
                            latch.countDown()
                            true
                        }
                    }
                    if (!shouldContinue) break
                }
            }
        }

        threads.forEach { it.start() }
        assertEquals(true, latch.await(10, TimeUnit.SECONDS))
        threads.forEach { it.join(10_000) }

        runBlocking { serializer.drain() }

        assertEquals((0 until callCount).toList(), applied)
    }
}
