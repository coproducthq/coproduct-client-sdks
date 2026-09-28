package app.coproduct.flutter

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * The framework adapter, kept to forwarding: every decision sits behind
 * DefaultNetworkSource, deliverAvailable, and the classifier, where the JVM
 * suite reaches it. Callbacks arrive on a connectivity thread and are posted to
 * the main thread before they touch the observer
 */
internal class ConnectivityNetworkSource(context: Context) : DefaultNetworkSource {
    private val connectivity: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    override fun hasDefaultNetwork(): Boolean = connectivity?.activeNetwork != null

    override fun register(events: DefaultNetworkEvents): NetworkRegistration {
        // A RuntimeException, so the observer reports it as a refused registration
        val manager = connectivity ?: throw IllegalStateException("no connectivity service")
        val onMain = MainThreadNetworkEvents(events) { block -> main.post(block) }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) =
                deliverAvailable(onMain, network, Build.VERSION.SDK_INT) {
                    manager.getNetworkCapabilities(network)?.let(::networkTypeOf)
                }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
                onMain.onClassified(network, networkTypeOf(capabilities))

            override fun onLost(network: Network) = onMain.onLost(network)
        }
        manager.registerDefaultNetworkCallback(callback)
        return NetworkRegistration { manager.unregisterNetworkCallback(callback) }
    }

    private fun networkTypeOf(capabilities: NetworkCapabilities) =
        NetworkTypeClassifier.classify(capabilities::hasTransport)
}
