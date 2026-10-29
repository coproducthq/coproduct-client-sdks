package app.coproduct

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities

/**
 * Source of connectivity facts. Production wraps ConnectivityManager's
 * default network callback. Tests inject a fake so a unit test can drive a
 * connectivity change without the Android connectivity stack. Implementations
 * must deliver updates serially: one at a time, in order, never overlapping
 * or reordered. [NetworkMonitor]'s dedup relies on that contract rather than
 * synchronizing dedup and delivery as a single atomic step
 */
internal interface NetworkPathSource {
    fun start(onUpdate: (NetworkPathFacts) -> Unit)

    fun stop()
}

/**
 * Thin adapter over ConnectivityManager's default network callback,
 * deliberately logic-free: everything worth testing lives behind the
 * [NetworkPathSource] seam
 */
internal class ConnectivityManagerPathSource(context: Context) : NetworkPathSource {
    private val connectivityManager =
        context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun start(onUpdate: (NetworkPathFacts) -> Unit) {
        val networkCallback =
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    connectivityManager.getNetworkCapabilities(network)?.let {
                        onUpdate(factsFrom(it))
                    }
                }

                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                    onUpdate(factsFrom(capabilities))
                }

                override fun onLost(network: Network) {
                    onUpdate(
                        NetworkPathFacts(satisfied = false, wifi = false, cellular = false, ethernet = false),
                    )
                }
            }
        callback = networkCallback
        connectivityManager.registerDefaultNetworkCallback(networkCallback)
    }

    override fun stop() {
        callback?.let { connectivityManager.unregisterNetworkCallback(it) }
        callback = null
    }

    private fun factsFrom(capabilities: NetworkCapabilities): NetworkPathFacts =
        NetworkPathFacts(
            satisfied = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            wifi = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
            cellular = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
            ethernet = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
        )
}

/**
 * Watches connectivity and reports the classified network_type on every
 * value change. The attribute is absent until the first path callback:
 * initialize is never blocked on the monitor, reads in that window fall
 * through conservatively, and the observer fanout corrects values when the
 * first callback lands
 */
internal class NetworkMonitor(
    private val source: NetworkPathSource,
    private val onChange: (String) -> Unit,
) {
    private val lock = Any()
    private var lastReported: String? = null

    fun start() {
        source.start { facts -> deliver(NetworkTypeClassifier.classify(facts)) }
    }

    fun stop() {
        source.stop()
    }

    /**
     * Deduplicates so path churn that lands on the same classification does
     * not enqueue redundant upserts. The core also stays silent on a no-op,
     * this just avoids the crossing. The dedup check and the onChange call
     * below are not atomic with each other. Correctness depends on the
     * source honoring the [NetworkPathSource] contract of serial, in-order
     * delivery, so two updates can never race each other into this method
     */
    private fun deliver(type: String) {
        val changed =
            synchronized(lock) {
                val isChanged = lastReported != type
                if (isChanged) lastReported = type
                isChanged
            }
        if (changed) onChange(type)
    }
}
