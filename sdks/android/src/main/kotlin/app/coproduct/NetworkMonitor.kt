package app.coproduct

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest

/** Connectivity facts one network update carries, decoupled from Android types so tests can fabricate updates. */
internal data class NetworkPathFacts(
    val satisfied: Boolean,
    val wifi: Boolean,
    val cellular: Boolean,
    val ethernet: Boolean,
)

/** Source of connectivity facts. Production wraps ConnectivityManager; tests inject a fake. */
internal interface NetworkPathSource {
    fun start(onUpdate: (NetworkPathFacts) -> Unit)
    fun cancel()
}

/** Thin adapter over ConnectivityManager, deliberately logic-free. */
internal class ConnectivityManagerSource(
    private val connectivityManager: ConnectivityManager,
) : NetworkPathSource {
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun start(onUpdate: (NetworkPathFacts) -> Unit) {
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                onUpdate(
                    NetworkPathFacts(
                        satisfied = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
                        wifi = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                        cellular = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                        ethernet = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                    ),
                )
            }

            override fun onLost(network: Network) {
                onUpdate(NetworkPathFacts(satisfied = false, wifi = false, cellular = false, ethernet = false))
            }
        }
        callback = cb
        connectivityManager.registerNetworkCallback(NetworkRequest.Builder().build(), cb)
    }

    override fun cancel() {
        callback?.let { connectivityManager.unregisterNetworkCallback(it) }
        callback = null
    }
}

/** Maps path facts to the network_type vocabulary. Pure, so unit-testable in isolation. */
internal object NetworkTypeClassifier {
    fun classify(satisfied: Boolean, wifi: Boolean, cellular: Boolean, ethernet: Boolean): String = when {
        !satisfied -> "none"
        wifi -> "wifi"
        cellular -> "cellular"
        ethernet -> "ethernet"
        else -> "other"
    }
}

/**
 * Watches connectivity and reports the classified network_type on every
 * value change. The attribute is absent until the first path callback.
 */
internal class NetworkMonitor(
    private val source: NetworkPathSource,
    private val onChange: (String) -> Unit,
) {
    private val lock = Any()
    private var lastReported: String? = null
    private var stopped = false

    fun start() {
        synchronized(lock) {
            if (stopped) return
            source.start { facts ->
                deliver(
                    NetworkTypeClassifier.classify(
                        satisfied = facts.satisfied,
                        wifi = facts.wifi,
                        cellular = facts.cellular,
                        ethernet = facts.ethernet,
                    ),
                )
            }
        }
    }

    fun cancel() {
        synchronized(lock) {
            stopped = true
            source.cancel()
        }
    }

    // Deduplicates so path churn landing on the same classification does not
    // enqueue redundant upserts
    private fun deliver(type: String) {
        val changed = synchronized(lock) {
            val isNew = lastReported != type
            if (isNew) lastReported = type
            isNew
        }
        if (changed) onChange(type)
    }
}
