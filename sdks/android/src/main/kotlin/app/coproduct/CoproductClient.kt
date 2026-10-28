package app.coproduct

import android.util.Log
import app.coproduct.paywall.FlagReader
import uniffi.coproduct_ffi_uniffi.BoolDelivery
import uniffi.coproduct_ffi_uniffi.CoproductClient as NativeCoproductClient
import uniffi.coproduct_ffi_uniffi.EvaluationHook
import uniffi.coproduct_ffi_uniffi.EvaluationStage
import uniffi.coproduct_ffi_uniffi.HandlerHandle
import uniffi.coproduct_ffi_uniffi.HookContext
import uniffi.coproduct_ffi_uniffi.HookHandle
import uniffi.coproduct_ffi_uniffi.IntDelivery
import uniffi.coproduct_ffi_uniffi.JsonDelivery
import uniffi.coproduct_ffi_uniffi.LifecycleEvent
import uniffi.coproduct_ffi_uniffi.LifecycleHandler
import uniffi.coproduct_ffi_uniffi.NumberDelivery
import uniffi.coproduct_ffi_uniffi.PollOutcome
import uniffi.coproduct_ffi_uniffi.ProviderState
import uniffi.coproduct_ffi_uniffi.StringDelivery

private const val LOG_TAG = "Coproduct"

private class ClosureLifecycleHandler(
    private val closure: (LifecycleEvent) -> Unit,
) : LifecycleHandler {
    override suspend fun onEvent(event: LifecycleEvent) = closure(event)
}

private class ClosureEvaluationHook(
    private val stage: EvaluationHookStage,
    private val closure: (EvaluationHookContext) -> Unit,
) : EvaluationHook {
    override fun onStage(stage: EvaluationStage, ctx: HookContext) {
        if (stage != bridge(this.stage)) return
        closure(
            EvaluationHookContext(
                stage = this.stage,
                flagKey = ctx.flagKey,
                value = ctx.value?.toDetailValue(),
                defaultValue = ctx.defaultValue.toDetailValue(),
                errorCode = ctx.errorCode,
            ),
        )
    }

    private fun bridge(wrapper: EvaluationHookStage): EvaluationStage = when (wrapper) {
        EvaluationHookStage.BEFORE -> EvaluationStage.BEFORE
        EvaluationHookStage.AFTER -> EvaluationStage.AFTER
        EvaluationHookStage.ERROR -> EvaluationStage.ERROR
        EvaluationHookStage.FINALLY -> EvaluationStage.FINALLY
    }
}

/** The full ergonomic wrapper around the generated native client. */
class CoproductClient internal constructor(
    private val inner: NativeCoproductClient,
) : FlagReader {
    private val identitySerializer = IdentitySerializer()

    // --- Typed getters (never throw) ---
    fun getBool(key: String, default: Boolean): Boolean = inner.getBool(key, default)
    override fun getString(key: String, default: String): String = inner.getString(key, default)
    fun getInt(key: String, default: Long): Long = inner.getInt(key, default)
    fun getNumber(key: String, default: Double): Double = inner.getNumber(key, default)
    fun getJson(key: String, default: String): String = inner.getJson(key, default)

    fun getBoolDetails(key: String, default: Boolean): FlagEvaluationDetails =
        inner.getBoolDetails(key, default).toPublic()

    fun getStringDetails(key: String, default: String): FlagEvaluationDetails =
        inner.getStringDetails(key, default).toPublic()

    fun getIntDetails(key: String, default: Long): FlagEvaluationDetails =
        inner.getIntDetails(key, default).toPublic()

    fun getNumberDetails(key: String, default: Double): FlagEvaluationDetails =
        inner.getNumberDetails(key, default).toPublic()

    fun getJsonDetails(key: String, default: String): FlagEvaluationDetails =
        inner.getJsonDetails(key, default).toPublic()

    // --- Identity (fire-and-forget) ---
    fun identify(userId: String, attributes: Map<String, AttributeValue> = emptyMap(), linkAnonymous: Boolean = true) {
        identitySerializer.enqueue {
            try {
                inner.identify(userId, attributes.toContextValues(), linkAnonymous)
            } catch (error: Throwable) {
                Log.e(LOG_TAG, "identify failed", error)
            }
        }
    }

    fun signOut() {
        identitySerializer.enqueue {
            try {
                inner.signOut()
            } catch (error: Throwable) {
                Log.e(LOG_TAG, "signOut failed", error)
            }
        }
    }

    fun setContext(targetingKey: String, attributes: Map<String, AttributeValue> = emptyMap()) {
        identitySerializer.enqueue {
            try {
                inner.setContext(targetingKey, attributes.toContextValues())
            } catch (error: Throwable) {
                Log.e(LOG_TAG, "setContext failed", error)
            }
        }
    }

    fun updateAttributes(attributes: Map<String, AttributeValue>) {
        identitySerializer.enqueue {
            try {
                inner.updateAttributes(attributes.toContextValues())
            } catch (error: Throwable) {
                Log.e(LOG_TAG, "updateAttributes failed", error)
            }
        }
    }

    fun removeAttributes(names: List<String>) {
        identitySerializer.enqueue {
            try {
                inner.removeAttributes(names)
            } catch (error: Throwable) {
                Log.e(LOG_TAG, "removeAttributes failed", error)
            }
        }
    }

    fun previousAnonymousId(): String? = inner.previousAnonymousId()

    /** Awaited once during initialize, before the instance is published. */
    internal suspend fun setAutoPopulatedNow(attributes: Map<String, AttributeValue>) {
        inner.setAutoPopulatedAttributes(attributes.toContextValues())
    }

    /** Ordered variant for live updates after initialize (e.g. NetworkMonitor). */
    internal fun setAutoPopulated(attributes: Map<String, AttributeValue>) {
        identitySerializer.enqueue { inner.setAutoPopulatedAttributes(attributes.toContextValues()) }
    }

    internal suspend fun pollNow(): PollOutcome = inner.pollNow()

    internal fun state(): ProviderState = inner.state()

    internal suspend fun shutdownInner() = inner.shutdown()

    // --- Observation ---
    fun observeBool(key: String, default: Boolean, handler: (Boolean) -> Unit): Cancellable {
        val native = inner.observeBool(key)
        return observeDrain(
            key = key, defaultValue = default, seed = native::seed, pollNext = native::pollNext,
            valueOf = { d: BoolDelivery -> (d as? BoolDelivery.Value)?.value },
            isClosed = { d: BoolDelivery -> d is BoolDelivery.Closed },
            cancelNative = native::cancel, destroyNative = native::destroy, handler = handler,
        )
    }

    fun observeString(key: String, default: String, handler: (String) -> Unit): Cancellable {
        val native = inner.observeString(key)
        return observeDrain(
            key = key, defaultValue = default, seed = native::seed, pollNext = native::pollNext,
            valueOf = { d: StringDelivery -> (d as? StringDelivery.Value)?.value },
            isClosed = { d: StringDelivery -> d is StringDelivery.Closed },
            cancelNative = native::cancel, destroyNative = native::destroy, handler = handler,
        )
    }

    fun observeInt(key: String, default: Long, handler: (Long) -> Unit): Cancellable {
        val native = inner.observeInt(key)
        return observeDrain(
            key = key, defaultValue = default, seed = native::seed, pollNext = native::pollNext,
            valueOf = { d: IntDelivery -> (d as? IntDelivery.Value)?.value },
            isClosed = { d: IntDelivery -> d is IntDelivery.Closed },
            cancelNative = native::cancel, destroyNative = native::destroy, handler = handler,
        )
    }

    fun observeNumber(key: String, default: Double, handler: (Double) -> Unit): Cancellable {
        val native = inner.observeNumber(key)
        return observeDrain(
            key = key, defaultValue = default, seed = native::seed, pollNext = native::pollNext,
            valueOf = { d: NumberDelivery -> (d as? NumberDelivery.Value)?.value },
            isClosed = { d: NumberDelivery -> d is NumberDelivery.Closed },
            cancelNative = native::cancel, destroyNative = native::destroy, handler = handler,
        )
    }

    fun observeJson(key: String, default: String, handler: (String) -> Unit): Cancellable {
        val native = inner.observeJson(key)
        return observeDrain(
            key = key, defaultValue = default, seed = native::seed, pollNext = native::pollNext,
            valueOf = { d: JsonDelivery -> (d as? JsonDelivery.Value)?.value },
            isClosed = { d: JsonDelivery -> d is JsonDelivery.Closed },
            cancelNative = native::cancel, destroyNative = native::destroy, handler = handler,
        )
    }

    // --- Handlers / hooks ---
    fun addHandler(event: LifecycleEvent, handler: (LifecycleEvent) -> Unit): Cancellable {
        val handle: HandlerHandle = inner.addHandler(event, ClosureLifecycleHandler(handler))
        return Cancellable { handle.cancel() }
    }

    fun addEvaluationHook(stage: EvaluationHookStage, handler: (EvaluationHookContext) -> Unit): Cancellable {
        val handle: HookHandle = inner.addEvaluationHook(ClosureEvaluationHook(stage, handler))
        return Cancellable { handle.cancel() }
    }
}
