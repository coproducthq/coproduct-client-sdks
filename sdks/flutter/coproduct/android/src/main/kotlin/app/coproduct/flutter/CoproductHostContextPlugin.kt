package app.coproduct.flutter

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/**
 * Answers host-context questions the Dart side cannot answer correctly on its
 * own. Deliberately small: it performs no upsert, holds no SDK state beyond the
 * session transaction's process-wide guard and failure latch, and knows nothing
 * about the SDK key or the evaluation core. The native library the core
 * runs in is still loaded directly rather than through this channel
 */
class CoproductHostContextPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    // Written on the platform thread by attach and detach, read on the task
    // queue by onMethodCall, so the two need a happens-before edge
    @Volatile private var channel: MethodChannel? = null
    // Internal so a test can attach a fake context without an engine
    @Volatile internal var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = registerChannel(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
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
    }
}
