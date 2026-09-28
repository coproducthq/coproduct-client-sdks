package app.coproduct.flutter

import io.flutter.plugin.common.EventChannel

/** What the observer is told about the default network, on the main thread */
internal interface DefaultNetworkEvents {
    /** A network became the default. Says nothing about its transport yet */
    fun onAvailable(network: Any)

    /** The default network's transport, already classified */
    fun onClassified(network: Any, networkType: String)

    fun onLost(network: Any)
}

/** One registration with the platform, released exactly once by the observer */
internal fun interface NetworkRegistration {
    fun unregister()
}

/** The platform side, behind an interface so the JVM suite can drive it */
internal interface DefaultNetworkSource {
    /** Throws a RuntimeException when the platform refuses the registration */
    fun register(events: DefaultNetworkEvents): NetworkRegistration

    fun hasDefaultNetwork(): Boolean
}

/** Hands every callback to the main thread, where the observer's state lives */
internal class MainThreadNetworkEvents(
    private val events: DefaultNetworkEvents,
    private val post: (() -> Unit) -> Unit,
) : DefaultNetworkEvents {
    override fun onAvailable(network: Any) = post { events.onAvailable(network) }

    override fun onClassified(network: Any, networkType: String) =
        post { events.onClassified(network, networkType) }

    override fun onLost(network: Any) = post { events.onLost(network) }
}

/**
 * Delivers onAvailable. From API 26 the platform always follows it with
 * onCapabilitiesChanged, which classifies, so nothing is read here. Before that
 * it may not, so one best-effort read classifies. A null read still reports
 * other, because a network was just reported available and nothing guarantees
 * a later callback: emitting nothing could leave the attribute absent for the
 * whole listen. A loss that does follow corrects it to none
 */
internal fun deliverAvailable(
    events: DefaultNetworkEvents,
    network: Any,
    sdkInt: Int,
    readNetworkType: () -> String?,
) {
    events.onAvailable(network)
    if (sdkInt >= 26) return
    events.onClassified(network, readNetworkType() ?: "other")
}

/**
 * Streams network_type to Dart. Every listen makes a fresh registration and
 * produces the current value, so the Dart side rechecks by listening again
 * rather than by asking. All state is touched only on the main thread: the
 * channel has no task queue, and the source posts its callbacks there
 */
internal class NetworkTypeObserver(
    private val source: DefaultNetworkSource,
) : EventChannel.StreamHandler {
    private var active: Listening? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        // Replacing a listen that is still active is this observer's own
        // guarantee. A hot restart relistens without a Dart cancel, and the
        // observer does not rely on the embedding cancelling first
        cancel()
        val epoch = epochFrom(arguments)
        if (epoch == null) {
            // Sent on the stream rather than thrown, the one path the Dart side
            // reads observation failures from
            events.error(INVALID_EPOCH, "network_type listen needs an integer epoch", null)
            return
        }
        val listening = Listening(epoch, events)
        val registration = try {
            source.register(listening)
        } catch (error: RuntimeException) {
            // The platform documents only that a refusal is a RuntimeException,
            // and the per-app cap has used more than one subclass
            events.error(REGISTRATION_FAILED, error.message, null)
            return
        }
        // Set only after registering, which is safe because every callback is
        // posted to this thread and so runs after this method returns
        listening.registration = registration
        active = listening
        // With no default network the platform makes no callback at all, so
        // this is the only way that state is ever reported
        if (!source.hasDefaultNetwork()) listening.emit("none")
    }

    override fun onCancel(arguments: Any?) = cancel()

    /** Idempotent, so a cancel and an engine detachment in either order are safe */
    fun cancel() {
        val listening = active ?: return
        active = null
        listening.registration?.unregister()
    }

    private inner class Listening(
        private val epoch: Long,
        private val sink: EventChannel.EventSink,
    ) : DefaultNetworkEvents {
        var registration: NetworkRegistration? = null
        private var current: Any? = null

        private val isActive get() = active === this

        override fun onAvailable(network: Any) {
            current = network
        }

        override fun onClassified(network: Any, networkType: String) {
            if (!isActive || network != current) return
            emit(networkType)
        }

        override fun onLost(network: Any) {
            // A switch may report the new network before losing the old one, so
            // only the loss of the current default means there is none
            if (!isActive || network != current) return
            current = null
            emit("none")
        }

        fun emit(networkType: String) {
            sink.success(mapOf("epoch" to epoch, "value" to networkType))
        }
    }

    companion object {
        const val INVALID_EPOCH = "invalid-epoch"
        const val REGISTRATION_FAILED = "registration-failed"

        /** The standard codec sends a Dart int as an Integer or a Long by size */
        fun epochFrom(arguments: Any?): Long? = when (arguments) {
            is Int -> arguments.toLong()
            is Long -> arguments
            else -> null
        }
    }
}
