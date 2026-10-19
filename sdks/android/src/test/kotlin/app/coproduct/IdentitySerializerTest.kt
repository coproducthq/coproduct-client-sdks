package app.coproduct

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class IdentitySerializerTest {
    @Test
    fun appliesOperationsInCallOrder() = runBlocking {
        val serializer = IdentitySerializer(scope = this)
        val applied = CopyOnWriteArrayList<Int>()

        serializer.enqueue { delay(20); applied.add(1) }
        serializer.enqueue { applied.add(2) }
        serializer.enqueue { applied.add(3) }
        serializer.drain()

        assertEquals(listOf(1, 2, 3), applied)
    }

    @Test
    fun enqueueReturnsImmediatelyWithoutWaitingForTheOperation() = runBlocking {
        val serializer = IdentitySerializer(scope = this)
        var ran = false
        serializer.enqueue { delay(10_000); ran = true }
        assertEquals(false, ran)
    }
}
