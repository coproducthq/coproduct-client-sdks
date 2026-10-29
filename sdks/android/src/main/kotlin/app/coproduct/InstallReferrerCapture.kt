package app.coproduct

import android.content.Context
import android.util.Log
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import com.android.installreferrer.api.InstallReferrerStateListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The seam [InstallReferrerCapture] fetches the Play Install Referrer
 * through, so a JVM test can hand back a known query string, or simulate a
 * failure, without touching the real Play Install Referrer Library. [fetch]
 * calls back exactly once, with `null` on any failure
 */
internal interface ReferrerSource {
    fun fetch(onResult: (String?) -> Unit)
}

/**
 * Default production source, backed by [InstallReferrerClient]. Connects,
 * reads the referrer query string on [InstallReferrerResponse.OK], and ends
 * the connection either way. Any other response code, or a service that
 * disconnects before responding, reports `null` rather than throwing
 */
internal class PlayInstallReferrerSource(private val context: Context) : ReferrerSource {
    override fun fetch(onResult: (String?) -> Unit) {
        val client = InstallReferrerClient.newBuilder(context).build()
        var settled = false

        fun finish(result: String?) {
            if (settled) return
            settled = true
            try {
                client.endConnection()
            } catch (error: Exception) {
                Log.w(LOG_TAG, "install referrer end connection failed", error)
            }
            onResult(result)
        }

        try {
            client.startConnection(
                object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        if (responseCode != InstallReferrerResponse.OK) {
                            finish(null)
                            return
                        }
                        val referrer =
                            try {
                                client.installReferrer?.installReferrer
                            } catch (error: Exception) {
                                Log.w(LOG_TAG, "install referrer read failed", error)
                                null
                            }
                        finish(referrer)
                    }

                    override fun onInstallReferrerServiceDisconnected() {
                        finish(null)
                    }
                },
            )
        } catch (error: Exception) {
            Log.w(LOG_TAG, "install referrer connection failed", error)
            finish(null)
        }
    }

    companion object {
        private const val LOG_TAG = "Coproduct"
    }
}

/**
 * Captures the Play Install Referrer once per process and folds it into
 * [UtmStore], publishing the result through [publish] when a client is
 * available. Install referrer attribution only matters on a cold, first-ever
 * launch, so a single best-effort attempt that no-ops on failure is
 * sufficient. Nothing here retries or runs again later in the process
 */
internal class InstallReferrerCapture(
    private val source: ReferrerSource,
    private val store: UtmStore,
    private val scope: CoroutineScope,
    private val publish: (Map<String, AttributeValue>) -> Unit,
    private val logFailure: (Exception) -> Unit = { e -> Log.w(LOG_TAG, "install referrer capture failed", e) },
) {
    /**
     * Fetches the referrer on [scope], which is expected to run off the
     * main thread, and, if any UTM parameters were found, captures and
     * publishes them. A `null` or empty referrer, an empty parse, or any
     * error along the way is a silent no-op
     */
    fun run() {
        scope.launch {
            try {
                val referrer = fetchReferrer()
                if (referrer.isNullOrEmpty()) return@launch
                val attributes = store.capture(referrer)
                if (attributes.isNotEmpty()) publish(attributes)
            } catch (error: Exception) {
                logFailure(error)
            }
        }
    }

    private suspend fun fetchReferrer(): String? =
        suspendCancellableCoroutine { continuation ->
            source.fetch { result -> continuation.resume(result) }
        }

    companion object {
        private const val LOG_TAG = "Coproduct"

        /**
         * Convenience entry point for the production path: builds the real
         * [PlayInstallReferrerSource] for [context] and starts the one-shot
         * capture on [scope], publishing through [publish] if it finds
         * anything
         */
        fun start(
            context: Context,
            store: UtmStore,
            scope: CoroutineScope,
            publish: (Map<String, AttributeValue>) -> Unit,
        ) {
            InstallReferrerCapture(PlayInstallReferrerSource(context), store, scope, publish).run()
        }
    }
}
