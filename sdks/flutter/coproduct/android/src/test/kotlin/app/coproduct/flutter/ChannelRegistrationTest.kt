package app.coproduct.flutter

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Records what the channel registers with. MethodChannel hands its task queue
 * to setMessageHandler, so a channel built without one registers null here
 */
private class RecordingMessenger : BinaryMessenger {
    val backgroundQueue = object : BinaryMessenger.TaskQueue {}
    var channel: String? = null
    var queue: BinaryMessenger.TaskQueue? = null

    override fun makeBackgroundTaskQueue(): BinaryMessenger.TaskQueue = backgroundQueue

    override fun makeBackgroundTaskQueue(
        options: BinaryMessenger.TaskQueueOptions,
    ): BinaryMessenger.TaskQueue = backgroundQueue

    override fun send(channel: String, message: ByteBuffer?) {}

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        this.channel = channel
        this.queue = null
    }

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?,
        taskQueue: BinaryMessenger.TaskQueue?,
    ) {
        this.channel = channel
        this.queue = taskQueue
    }
}

class ChannelRegistrationTest {
    @Test fun theChannelRunsOnABackgroundTaskQueue() {
        // beginSession commits to disk under a process-wide lock, so a handler
        // left on the platform thread would block the UI for the write
        val messenger = RecordingMessenger()
        CoproductHostContextPlugin.registerChannel(messenger, object : MethodChannel.MethodCallHandler {
            override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {}
        })
        assertEquals("app.coproduct.flutter/host_context", messenger.channel)
        assertSame(messenger.backgroundQueue, messenger.queue)
    }
}
