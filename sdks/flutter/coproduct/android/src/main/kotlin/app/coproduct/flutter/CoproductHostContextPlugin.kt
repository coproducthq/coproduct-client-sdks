package app.coproduct.flutter

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/**
 * Answers host-context questions the Dart side cannot answer correctly on its
 * own, and streams network_type. Deliberately small: it performs no upsert,
 * holds no SDK state beyond the session transaction's process-wide guard and
 * failure latch and this engine's one network observation, and knows nothing
 * about the SDK key or the evaluation core. The native library the core runs in
 * is still loaded directly rather than through these channels
 */
class CoproductHostContextPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    // Written on the platform thread by attach and detach, read on the task
    // queue by onMethodCall, so the two need a happens-before edge
    @Volatile private var channel: MethodChannel? = null
    // Internal so a test can attach a fake context without an engine
    @Volatile internal var context: Context? = null
    // Main-thread only, like the observer it holds
    private var networkBinding: NetworkChannelBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = registerChannel(binding.binaryMessenger, this)
        networkBinding = NetworkChannelBinding(
            binding.binaryMessenger,
            ConnectivityNetworkSource(binding.applicationContext),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        networkBinding?.detach()
        networkBinding = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readDeviceType" -> result.success(readDeviceType())
            "beginSession" -> result.success(beginSession()?.toChannel())
            else -> result.notImplemented()
        }
    }

    /**
     * Null tells the Dart side the store failed. A detached engine has no
     * context to open the store with, which is the same outcome for the caller
     */
    private fun beginSession(): SessionPair? {
        val appContext = context ?: return null
        return sessionFor(appContext)
    }

    /**
     * Pure plumbing: it reads the two configuration values and hands the feature
     * lookup over, so every classification decision stays where a test can reach it
     */
    private fun readDeviceType(): String? {
        val appContext = context ?: return null
        val configuration = appContext.resources.configuration
        return DeviceClassifier.classify(
            configuration.uiMode and Configuration.UI_MODE_TYPE_MASK,
            configuration.smallestScreenWidthDp,
            appContext.packageManager::hasSystemFeature,
        )
    }

    companion object {
        private const val CHANNEL_NAME = "app.coproduct.flutter/host_context"
        private const val NETWORK_CHANNEL_NAME = "app.coproduct.flutter/network_type"

        /**
         * The production session wiring: the real preferences adapter and the
         * process-wide shared state
         */
        internal fun sessionFor(appContext: Context): SessionPair? =
            SessionStore(SharedPreferencesSessionStorage(appContext)).begin()

        /**
         * A background task queue, because the platform thread is the UI thread
         * and beginSession commits to disk under a process-wide lock. Separate
         * from attach so a test can see which queue the channel registered with
         */
        internal fun registerChannel(
            messenger: BinaryMessenger,
            handler: MethodChannel.MethodCallHandler,
        ): MethodChannel {
            val taskQueue = messenger.makeBackgroundTaskQueue()
            return MethodChannel(messenger, CHANNEL_NAME, StandardMethodCodec.INSTANCE, taskQueue)
                .also { it.setMethodCallHandler(handler) }
        }

        /**
         * No task queue, unlike the method channel: the observer's state lives on
         * the main thread, where its callbacks are posted. Separate from attach so
         * a test can see which queue the channel registered with
         */
        internal fun registerNetworkChannel(
            messenger: BinaryMessenger,
            handler: EventChannel.StreamHandler,
        ): EventChannel =
            EventChannel(messenger, NETWORK_CHANNEL_NAME).also { it.setStreamHandler(handler) }
    }
}

/**
 * This engine's network observation, apart from attach and detach so a JVM
 * test can drive it without an engine
 */
internal class NetworkChannelBinding(messenger: BinaryMessenger, source: DefaultNetworkSource) {
    private val observer = NetworkTypeObserver(source)
    private val channel = CoproductHostContextPlugin.registerNetworkChannel(messenger, observer)

    /** A no-op when Dart already cancelled, so the two cannot unregister twice */
    fun detach() {
        channel.setStreamHandler(null)
        observer.cancel()
    }
}
