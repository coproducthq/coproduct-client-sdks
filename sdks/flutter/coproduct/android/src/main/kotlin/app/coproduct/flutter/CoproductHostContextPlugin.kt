package app.coproduct.flutter

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/// Answers host-context questions the Dart side cannot answer correctly on its
/// own. Deliberately small: it holds no SDK state, performs no upsert, and knows
/// nothing about the SDK key or the evaluation core. The native library the core
/// runs in is still loaded directly rather than through this channel.
class CoproductHostContextPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        // A background task queue, because this handler performs disk work under
        // a process-global lock and the platform thread is the UI thread
        val taskQueue = binding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(
            binding.binaryMessenger,
            CHANNEL_NAME,
            StandardMethodCodec.INSTANCE,
            taskQueue,
        ).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readDeviceType" -> result.success(readDeviceType())
            else -> result.notImplemented()
        }
    }

    /// Pure plumbing: it reads the two configuration values and hands the feature
    /// lookup over, so every classification decision stays where a test can reach it
    private fun readDeviceType(): String? {
        val appContext = context ?: return null
        val configuration = appContext.resources.configuration
        return DeviceClassifier.classify(
            configuration.uiMode and Configuration.UI_MODE_TYPE_MASK,
            configuration.smallestScreenWidthDp,
            appContext.packageManager::hasSystemFeature,
        )
    }

    private companion object {
        const val CHANNEL_NAME = "app.coproduct.flutter/host_context"
    }
}
