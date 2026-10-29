package app.coproduct

import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The fire-and-forget identity API must still apply its calls in the order
 * they were made. The serializer is what guarantees that, independent of
 * how long any single mutation takes, mirroring the iOS
 * IdentitySerializerTests ordering guarantee
 */
class IdentitySerializerTest {
    private fun serializerIn(scope: TestScope) = IdentitySerializer(scope, logError = {})

    @Test
    fun enqueuePreservesCallOrderEvenWhenEarlierWorkIsSlower() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val serializer = serializerIn(scope)
            val order = mutableListOf<Int>()
            val total = 10

            // Earlier items sleep longer. Without serialization the shorter
            // later items would finish first and the recorded order would
            // be inverted
            for (index in 0 until total) {
                serializer.enqueue {
                    delay((total - index) * 2L)
                    order.add(index)
                }
            }

            scope.advanceUntilIdle()
            assertEquals((0 until total).toList(), order)
        }

    @Test
    fun enqueueAppliesThreeCallsInOrder() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val serializer = serializerIn(scope)
            val order = mutableListOf<String>()

            serializer.enqueue { order.add("A") }
            serializer.enqueue { order.add("B") }
            serializer.enqueue { order.add("C") }

            scope.advanceUntilIdle()
            assertEquals(listOf("A", "B", "C"), order)
        }

    @Test
    fun aFailingMutationIsLoggedAndNeverBlocksALaterOne() =
        runTest {
            val scope = TestScope(StandardTestDispatcher(testScheduler))
            val errors = mutableListOf<Throwable>()
            val serializer = IdentitySerializer(scope, logError = { errors.add(it) })
            var laterRan = false

            serializer.enqueue { throw IllegalStateException("identify failed") }
            serializer.enqueue { laterRan = true }

            scope.advanceUntilIdle()
            assertEquals(true, laterRan)
            assertEquals(1, errors.size)
            assertEquals("identify failed", errors.single().message)
        }
}
