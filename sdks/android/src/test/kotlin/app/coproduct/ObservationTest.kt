package app.coproduct

import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

private sealed class FakeDelivery {
    data class Value(val value: Int?) : FakeDelivery()
    object Closed : FakeDelivery()
}

class ObservationTest {
    @Test
    fun deliversSeedThenValuesInOrder() {
        val received = CopyOnWriteArrayList<Int>()
        val latch = CountDownLatch(3)
        val queue = LinkedBlockingQueue<FakeDelivery>()
        queue.put(FakeDelivery.Value(2))
        queue.put(FakeDelivery.Value(3))
        queue.put(FakeDelivery.Closed)

        val cancellable = observeDrain(
            key = "flag",
            defaultValue = 0,
            seed = { 1 },
            pollNext = { queue.take() },
            valueOf = { d: FakeDelivery -> (d as? FakeDelivery.Value)?.value },
            isClosed = { d: FakeDelivery -> d is FakeDelivery.Closed },
            cancelNative = {},
            destroyNative = {},
            mainDispatcher = Dispatchers.Unconfined,
            handler = { value -> received.add(value); latch.countDown() },
        )

        assertEquals(true, latch.await(1, TimeUnit.SECONDS))
        assertEquals(listOf(1, 2, 3), received)
        cancellable.cancel()
    }

    @Test
    fun cancelIsIdempotentAndRunsCleanupOnce() {
        val cleanupCount = AtomicInteger(0)
        val cancellable = observeDrain<Int, FakeDelivery>(
            key = "flag",
            defaultValue = 0,
            seed = { null },
            pollNext = { FakeDelivery.Closed },
            valueOf = { null },
            isClosed = { true },
            cancelNative = { cleanupCount.incrementAndGet() },
            destroyNative = {},
            mainDispatcher = Dispatchers.Unconfined,
            handler = {},
        )
        cancellable.cancel()
        cancellable.cancel()
        assertEquals(1, cleanupCount.get())
    }

    @Test
    fun aKeyWithNoUsableValueResolvesToDefault() {
        val received = CopyOnWriteArrayList<Int>()
        val latch = CountDownLatch(1)
        observeDrain(
            key = "flag",
            defaultValue = 99,
            seed = { null },
            pollNext = { FakeDelivery.Closed },
            valueOf = { null },
            isClosed = { it is FakeDelivery.Closed },
            cancelNative = {},
            destroyNative = {},
            mainDispatcher = Dispatchers.Unconfined,
            handler = { value -> received.add(value); latch.countDown() },
        )
        assertEquals(true, latch.await(1, TimeUnit.SECONDS))
        assertEquals(listOf(99), received)
    }
}
