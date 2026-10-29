package app.coproduct

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.ProviderState

/**
 * A minimal stand-in for the public CoproductClient wrapper. The generated
 * native client only exposes a non-functional fake constructor (`NoHandle`),
 * so [Instances]'s registry and generation-fence logic is tested against
 * this instead, mirroring the iOS InstancesTests approach of driving the
 * registry with a test double rather than a real FFI client
 */
private class FakeClient(var state: ProviderState = ProviderState.READY)

class InstancesTest {
    private fun instancesOf(
        shutdownCalls: MutableList<FakeClient> = mutableListOf(),
        nowNanos: () -> Long = { System.nanoTime() },
        sleepNanos: suspend (Long) -> Unit = {},
    ) = Instances<FakeClient>(
        stateOf = { it.state },
        shutdownClient = { shutdownCalls.add(it) },
        nowNanos = nowNanos,
        sleepNanos = sleepNanos,
    )

    @Test
    fun defaultInstanceStartsNull() {
        val instances = instancesOf()
        assertNull(instances.defaultInstance())
    }

    @Test
    fun defaultInstanceReflectsTheMostRecentlyStoredClient() {
        val instances = instancesOf()

        val clientA = FakeClient()
        assertTrue(instances.storeForTesting(clientA))
        assertSame(clientA, instances.defaultInstance())

        // A second store replaces the first, exercising "replace" rather than
        // only "set once"
        val clientB = FakeClient()
        assertTrue(instances.storeForTesting(clientB))
        assertSame(clientB, instances.defaultInstance())
    }

    @Test
    fun aStaleInitDoesNotOverwriteANewerInstance() =
        runTest {
            val instances = instancesOf()
            val startedA = CompletableDeferred<Unit>()
            val gateA = CompletableDeferred<Unit>()
            val clientA = FakeClient()
            val clientB = FakeClient()

            // Claims the registry slot and pauses inside build, so its
            // claimed generation (0) is captured before shutdown bumps it
            val resultA =
                async {
                    instances.initialize(
                        sdkKey = "a",
                        startupTimeoutSecs = 0,
                        scopeFactory = { CoroutineScope(SupervisorJob() + Dispatchers.Default) },
                        build = {
                            startedA.complete(Unit)
                            gateA.await()
                            clientA
                        },
                    )
                }

            // Wait until A's build has actually started (and so has already
            // claimed its generation) before racing it with a shutdown
            startedA.await()
            instances.shutdown()

            // A fresh initialize after the shutdown claims the new generation
            // and publishes immediately
            val stored =
                instances.initialize(
                    sdkKey = "b",
                    startupTimeoutSecs = 0,
                    scopeFactory = { CoroutineScope(SupervisorJob() + Dispatchers.Default) },
                    build = { clientB },
                )
            assertSame(clientB, stored)

            gateA.complete(Unit)
            try {
                resultA.await()
                fail("expected the stale initialize to be cancelled rather than resurrect or overwrite the newer instance")
            } catch (_: CancellationException) {
                // expected: the stale generation can never publish
            }

            // The newer instance must still be the one in the registry
            assertSame(clientB, instances.defaultInstance())
        }

    @Test
    fun waitForFirstPollReturnsImmediatelyWhenStartupTimeoutIsZero() =
        runTest {
            val instances = instancesOf()
            val client = FakeClient(state = ProviderState.NOT_READY)
            assertTrue(instances.waitForFirstPoll(client, startupTimeoutSecs = 0))
        }

    @Test
    fun waitForFirstPollTimesOutToFalseWhenStateStaysNotReady() =
        runTest {
            var fakeNowNanos = 0L
            val sleeps = mutableListOf<Long>()
            val instances =
                instancesOf(
                    nowNanos = { fakeNowNanos },
                    sleepNanos = { nanos ->
                        sleeps.add(nanos)
                        fakeNowNanos += nanos
                    },
                )
            val client = FakeClient(state = ProviderState.NOT_READY)
            // Registered as current so the loop runs out the fake clock
            // rather than exiting early on the currency check
            assertTrue(instances.storeForTesting(client))

            val ready = instances.waitForFirstPoll(client, startupTimeoutSecs = 1)

            assertFalse(ready)
            assertTrue("expected the fake clock to be advanced by at least one sleep", sleeps.isNotEmpty())
        }

    @Test
    fun waitForFirstPollReturnsFalseWhenAShutdownRacesTheWait() =
        runTest {
            val instances = instancesOf()
            val client = FakeClient(state = ProviderState.NOT_READY)
            assertTrue(instances.storeForTesting(client))

            instances.shutdown()

            val ready = instances.waitForFirstPoll(client, startupTimeoutSecs = 5)
            assertFalse(ready)
        }
}
