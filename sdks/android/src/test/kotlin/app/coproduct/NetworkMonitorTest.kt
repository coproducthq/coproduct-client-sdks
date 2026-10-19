package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Test

private class FakeNetworkPathSource : NetworkPathSource {
    private var onUpdate: ((NetworkPathFacts) -> Unit)? = null
    var cancelled = false

    override fun start(onUpdate: (NetworkPathFacts) -> Unit) {
        this.onUpdate = onUpdate
    }

    override fun cancel() {
        cancelled = true
    }

    fun push(facts: NetworkPathFacts) {
        onUpdate?.invoke(facts)
    }
}

class NetworkMonitorTest {
    @Test
    fun classifiesWifiCellularEthernetAndNone() {
        assertEquals("wifi", NetworkTypeClassifier.classify(satisfied = true, wifi = true, cellular = false, ethernet = false))
        assertEquals("cellular", NetworkTypeClassifier.classify(satisfied = true, wifi = false, cellular = true, ethernet = false))
        assertEquals("ethernet", NetworkTypeClassifier.classify(satisfied = true, wifi = false, cellular = false, ethernet = true))
        assertEquals("none", NetworkTypeClassifier.classify(satisfied = false, wifi = true, cellular = true, ethernet = true))
        assertEquals("other", NetworkTypeClassifier.classify(satisfied = true, wifi = false, cellular = false, ethernet = false))
    }

    @Test
    fun deduplicatesConsecutiveIdenticalClassifications() {
        val source = FakeNetworkPathSource()
        val reported = mutableListOf<String>()
        val monitor = NetworkMonitor(source) { reported.add(it) }
        monitor.start()

        source.push(NetworkPathFacts(satisfied = true, wifi = true, cellular = false, ethernet = false))
        source.push(NetworkPathFacts(satisfied = true, wifi = true, cellular = false, ethernet = false))
        source.push(NetworkPathFacts(satisfied = true, wifi = false, cellular = true, ethernet = false))

        assertEquals(listOf("wifi", "cellular"), reported)
    }

    @Test
    fun cancelDelegatesToSource() {
        val source = FakeNetworkPathSource()
        val monitor = NetworkMonitor(source) {}
        monitor.cancel()
        assertEquals(true, source.cancelled)
    }
}
