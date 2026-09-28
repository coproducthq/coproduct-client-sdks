package app.coproduct.flutter

import io.flutter.plugin.common.EventChannel
import org.junit.Assert.assertEquals
import org.junit.Test

/** Records what the observer sent to Dart */
private class RecordingSink : EventChannel.EventSink {
    val events = mutableListOf<Any?>()
    val errors = mutableListOf<String>()

    override fun success(event: Any?) {
        events.add(event)
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        errors.add(errorCode)
    }

    override fun endOfStream() {
        events.add("endOfStream")
    }
}

/**
 * Stands in for ConnectivityManager. It never calls back on its own: a test
 * delivers each callback itself, which is what the adapter's post to the main
 * thread amounts to
 */
private class FakeSource : DefaultNetworkSource {
    var hasDefault = true
    var refusal: RuntimeException? = null
    val registered = mutableListOf<DefaultNetworkEvents>()
    var unregisters = 0
    val live get() = registered.size - unregisters
    val latest get() = registered.last()

    override fun register(events: DefaultNetworkEvents): NetworkRegistration {
        refusal?.let { throw it }
        registered.add(events)
        return NetworkRegistration { unregisters++ }
    }

    override fun hasDefaultNetwork() = hasDefault
}

private fun envelope(epoch: Long, value: String) = mapOf("epoch" to epoch, "value" to value)

class NetworkTypeObserverTest {
    @Test fun withNoDefaultNetworkTheListenEmitsNone() {
        // The platform makes no callback at all in this state, so this is the
        // only way the Dart side ever learns it
        val source = FakeSource().apply { hasDefault = false }
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(7, sink)
        assertEquals(listOf(envelope(7, "none")), sink.events)
    }

    @Test fun aPresentNetworkIsReportedFromItsCallbacksNotAtListen() {
        val source = FakeSource()
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(7, sink)
        assertEquals(emptyList<Any?>(), sink.events)
        source.latest.onAvailable("wifi-network")
        source.latest.onClassified("wifi-network", "wifi")
        assertEquals(listOf(envelope(7, "wifi")), sink.events)
    }

    @Test fun aBlockedDefaultNetworkReportsNoneUntilItsCallbackCorrectsIt() {
        // getActiveNetwork returns null while the default network is blocked for
        // this app, and the default-network callback then reports the transport
        val source = FakeSource().apply { hasDefault = false }
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(1, sink)
        source.latest.onAvailable("wifi-network")
        source.latest.onClassified("wifi-network", "wifi")
        assertEquals(listOf(envelope(1, "none"), envelope(1, "wifi")), sink.events)
    }

    @Test fun everyEventEchoesTheListensEpochWhateverItsSize() {
        // The standard codec sends a Dart int that fits 32 bits as an Integer
        // and a larger one as a Long
        val small = RecordingSink()
        NetworkTypeObserver(FakeSource().apply { hasDefault = false }).onListen(3, small)
        val large = RecordingSink()
        NetworkTypeObserver(FakeSource().apply { hasDefault = false }).onListen(5_000_000_000L, large)
        assertEquals(listOf(envelope(3, "none")), small.events)
        assertEquals(listOf(envelope(5_000_000_000L, "none")), large.events)
    }

    @Test fun aListenWithoutAnIntegerEpochIsAStreamErrorAndRegistersNothing() {
        for (arguments in listOf(null, "7", 7.0, true)) {
            val source = FakeSource()
            val sink = RecordingSink()
            NetworkTypeObserver(source).onListen(arguments, sink)
            assertEquals("arguments $arguments", listOf(NetworkTypeObserver.INVALID_EPOCH), sink.errors)
            assertEquals("arguments $arguments", 0, source.registered.size)
        }
    }

    @Test fun aRegistrationRefusalIsAStreamErrorRatherThanAThrow() {
        // A refusal reaches Dart on the stream, the one path it reads observation
        // failures from, never as a throw from the listen handler. The per-app cap
        // has used more than one RuntimeException subclass, and a missing
        // permission is a SecurityException, which is one too
        val refusals = listOf(
            IllegalArgumentException("too many requests"),
            SecurityException("permission denied"),
            IllegalStateException("no connectivity service"),
        )
        for (refusal in refusals) {
            val source = FakeSource().apply { this.refusal = refusal }
            val sink = RecordingSink()
            val observer = NetworkTypeObserver(source)
            observer.onListen(1, sink)
            assertEquals(listOf(NetworkTypeObserver.REGISTRATION_FAILED), sink.errors)
            assertEquals(emptyList<Any?>(), sink.events)
            observer.cancel()
            assertEquals(0, source.unregisters)
        }
    }

    @Test fun aHandoverReportingTheNewNetworkFirstNeverEndsOnNone() {
        // A default-network switch may report the new network before, or
        // instead of, losing the old one, so only losing the current default
        // means there is none
        val source = FakeSource()
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(1, sink)
        val events = source.latest
        events.onAvailable("wifi-network")
        events.onClassified("wifi-network", "wifi")
        events.onAvailable("cell-network")
        events.onClassified("cell-network", "cellular")
        events.onLost("wifi-network")
        assertEquals(listOf(envelope(1, "wifi"), envelope(1, "cellular")), sink.events)
        events.onLost("cell-network")
        assertEquals(envelope(1, "none"), sink.events.last())
    }

    @Test fun aClassificationForANetworkThatIsNotTheDefaultIsIgnored() {
        val source = FakeSource()
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(1, sink)
        source.latest.onClassified("unknown-network", "wifi")
        assertEquals(emptyList<Any?>(), sink.events)
    }

    @Test fun cancelUnregistersExactlyOnceWhateverTheOrder() {
        // A listen cancel and an engine detachment both cancel, in either order
        val source = FakeSource()
        val observer = NetworkTypeObserver(source)
        observer.onListen(1, RecordingSink())
        observer.onCancel(null)
        observer.cancel()
        assertEquals(1, source.unregisters)

        val other = FakeSource()
        val detachedFirst = NetworkTypeObserver(other)
        detachedFirst.onListen(1, RecordingSink())
        detachedFirst.cancel()
        detachedFirst.onCancel(null)
        assertEquals(1, other.unregisters)
    }

    @Test fun aCallbackAfterCancelIsNotDelivered() {
        val source = FakeSource()
        val sink = RecordingSink()
        val observer = NetworkTypeObserver(source)
        observer.onListen(1, sink)
        val stale = source.latest
        observer.cancel()
        stale.onAvailable("wifi-network")
        stale.onClassified("wifi-network", "wifi")
        stale.onLost("wifi-network")
        assertEquals(emptyList<Any?>(), sink.events)
    }

    @Test fun aLateCallbackForTheCurrentNetworkIsNotDeliveredAfterCancel() {
        // The network was already the default when the listen was cancelled,
        // so only the listen's own cancelled state stops a classification or a
        // loss that was queued before the cancel
        val source = FakeSource()
        val sink = RecordingSink()
        val observer = NetworkTypeObserver(source)
        observer.onListen(1, sink)
        val stale = source.latest
        stale.onAvailable("wifi-network")
        observer.cancel()
        stale.onClassified("wifi-network", "wifi")
        stale.onLost("wifi-network")
        assertEquals(emptyList<Any?>(), sink.events)
    }

    @Test fun aListenWhileListeningReplacesThePreviousOne() {
        // A Dart hot restart relistens without cancelling its subscription, so
        // the observer must not depend on a cancel arriving first
        val source = FakeSource()
        val observer = NetworkTypeObserver(source)
        val first = RecordingSink()
        observer.onListen(1, first)
        val stale = source.latest
        val second = RecordingSink()
        observer.onListen(2, second)
        assertEquals(1, source.live)
        stale.onAvailable("network")
        stale.onClassified("network", "wifi")
        source.latest.onAvailable("network")
        source.latest.onClassified("network", "cellular")
        assertEquals(emptyList<Any?>(), first.events)
        assertEquals(listOf(envelope(2, "cellular")), second.events)
    }

    @Test fun repeatedListenAndCancelCyclesLeaveAtMostOneRegistration() {
        // The platform caps outstanding callbacks per app, so a leak here
        // eventually refuses every registration in the process
        val source = FakeSource()
        val observer = NetworkTypeObserver(source)
        repeat(50) { cycle ->
            observer.onListen(cycle, RecordingSink())
            assertEquals(1, source.live)
            if (cycle % 2 == 0) observer.onCancel(null)
        }
        observer.cancel()
        assertEquals(0, source.live)
        assertEquals(50, source.registered.size)
    }

    @Test fun cancellingOneObserverLeavesAnotherObserving() {
        // One observer per engine. Two instances against fakes, not two real
        // engines
        val firstSource = FakeSource()
        val secondSource = FakeSource()
        val first = NetworkTypeObserver(firstSource)
        val second = NetworkTypeObserver(secondSource)
        val sink = RecordingSink()
        first.onListen(1, RecordingSink())
        second.onListen(2, sink)
        first.cancel()
        secondSource.latest.onAvailable("network")
        secondSource.latest.onClassified("network", "ethernet")
        assertEquals(listOf(envelope(2, "ethernet")), sink.events)
        assertEquals(0, secondSource.unregisters)
    }

    @Test fun belowApi26OnAvailableClassifiesFromOneRead() {
        val source = FakeSource()
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(1, sink)
        var reads = 0
        deliverAvailable(source.latest, "network", sdkInt = 25) { reads++; "cellular" }
        assertEquals(1, reads)
        assertEquals(listOf(envelope(1, "cellular")), sink.events)
    }

    @Test fun belowApi26ANetworkWithNoCapabilitiesIsOtherUntilSomethingCorrectsIt() {
        // Neither a capabilities callback nor a loss is guaranteed to follow
        // here, so emitting nothing could leave the attribute absent for the
        // whole listen. A network was just reported available, and connected
        // but unclassified is other. A loss that does follow corrects it
        val source = FakeSource()
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(1, sink)
        deliverAvailable(source.latest, "network", sdkInt = 24) { null }
        assertEquals(listOf(envelope(1, "other")), sink.events)
        source.latest.onLost("network")
        assertEquals(listOf(envelope(1, "other"), envelope(1, "none")), sink.events)
    }

    @Test fun fromApi26OnAvailableMakesNoCapabilitiesRead() {
        // The platform guarantees onCapabilitiesChanged follows, and a
        // synchronous read inside a callback can race it
        val source = FakeSource()
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(1, sink)
        var reads = 0
        deliverAvailable(source.latest, "network", sdkInt = 26) { reads++; "wifi" }
        assertEquals(0, reads)
        assertEquals(emptyList<Any?>(), sink.events)
        source.latest.onClassified("network", "wifi")
        assertEquals(listOf(envelope(1, "wifi")), sink.events)
    }

    @Test fun anInvalidEpochReleasesTheListenItReplaced() {
        // Both paths cancel before validating, so a relisten that turns out
        // invalid must still release what it replaced
        val source = FakeSource()
        val observer = NetworkTypeObserver(source)
        val first = RecordingSink()
        observer.onListen(1, first)
        val stale = source.latest
        val second = RecordingSink()
        observer.onListen("x", second)
        assertEquals(1, source.unregisters)
        assertEquals(listOf(NetworkTypeObserver.INVALID_EPOCH), second.errors)
        stale.onAvailable("wifi-network")
        stale.onClassified("wifi-network", "wifi")
        assertEquals(emptyList<Any?>(), first.events)
        assertEquals(emptyList<Any?>(), second.events)
    }

    @Test fun aRefusedRelistenReleasesTheListenItReplaced() {
        val source = FakeSource()
        val observer = NetworkTypeObserver(source)
        val first = RecordingSink()
        observer.onListen(1, first)
        source.refusal = IllegalStateException("no connectivity service")
        val second = RecordingSink()
        observer.onListen(2, second)
        assertEquals(1, source.unregisters)
        assertEquals(listOf(NetworkTypeObserver.REGISTRATION_FAILED), second.errors)
    }

    @Test fun everyCallbackIsHandedToTheMainThread() {
        // Framework callbacks arrive on a connectivity thread. Nothing may reach
        // the observer until the main thread runs it
        val posted = mutableListOf<() -> Unit>()
        val source = FakeSource()
        val sink = RecordingSink()
        NetworkTypeObserver(source).onListen(1, sink)
        val onMain = MainThreadNetworkEvents(source.latest) { posted.add(it) }
        onMain.onAvailable("network")
        onMain.onClassified("network", "wifi")
        onMain.onLost("network")
        assertEquals(emptyList<Any?>(), sink.events)
        assertEquals(3, posted.size)
        posted.forEach { it() }
        assertEquals(listOf(envelope(1, "wifi"), envelope(1, "none")), sink.events)
    }
}
