package app.coproduct.flutter

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Test

private const val NETWORK_CHANNEL = "app.coproduct.flutter/network_type"

/** Stands in for ConnectivityManager, recording what the binding registers and releases */
private class BindingFakeSource : DefaultNetworkSource {
    val registered = mutableListOf<DefaultNetworkEvents>()
    var unregisters = 0

    override fun register(events: DefaultNetworkEvents): NetworkRegistration {
        registered.add(events)
        return NetworkRegistration { unregisters++ }
    }

    override fun hasDefaultNetwork() = true
}

/**
 * Records the handler each channel registers and the messages it sends, so a
 * test can drive the event channel's own listen protocol rather than the
 * observer directly
 */
private class BindingRecordingMessenger : BinaryMessenger {
    // The last handler a channel ever installed, kept even after
    // setMessageHandler(channel, null) clears registration, so a test can
    // still exercise a message arriving at the handler object directly, the
    // way one already in flight when unregistration lands would
    private val everInstalled = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
    val sent = mutableListOf<Pair<String, ByteBuffer?>>()

    override fun makeBackgroundTaskQueue(): BinaryMessenger.TaskQueue = object : BinaryMessenger.TaskQueue {}

    override fun makeBackgroundTaskQueue(
        options: BinaryMessenger.TaskQueueOptions,
    ): BinaryMessenger.TaskQueue = makeBackgroundTaskQueue()

    override fun send(channel: String, message: ByteBuffer?) {
        sent.add(channel to message)
    }

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        sent.add(channel to message)
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        if (handler != null) everInstalled[channel] = handler
    }

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?,
        taskQueue: BinaryMessenger.TaskQueue?,
    ) = setMessageHandler(channel, handler)

    fun deliver(channel: String, method: String, arguments: Any?) {
        val encoded = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
        encoded.flip()
        everInstalled.getValue(channel).onMessage(encoded) {}
    }
}

class NetworkChannelBindingTest {
    @Test fun detachReleasesTheRegistrationAndACancelAfterwardUnregistersNothingMore() {
        val messenger = BindingRecordingMessenger()
        val source = BindingFakeSource()
        val binding = NetworkChannelBinding(messenger, source)
        messenger.deliver(NETWORK_CHANNEL, "listen", 1)
        assertEquals(1, source.registered.size)

        binding.detach()
        assertEquals(1, source.unregisters)

        messenger.deliver(NETWORK_CHANNEL, "cancel", null)
        assertEquals(1, source.unregisters)
    }

    @Test fun theChannelWiringCarriesAClassifiedValueBackToDart() {
        val messenger = BindingRecordingMessenger()
        val source = BindingFakeSource()
        NetworkChannelBinding(messenger, source)
        messenger.deliver(NETWORK_CHANNEL, "listen", 4)
        val events = source.registered.last()
        events.onAvailable("network")
        events.onClassified("network", "wifi")

        val sent = messenger.sent.last { it.first == NETWORK_CHANNEL }.second!!
        sent.rewind()
        val decoded = StandardMethodCodec.INSTANCE.decodeEnvelope(sent)
        assertEquals(mapOf("epoch" to 4L, "value" to "wifi"), decoded)
    }
}
