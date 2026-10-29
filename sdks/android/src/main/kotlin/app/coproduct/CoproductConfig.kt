package app.coproduct

import uniffi.coproduct_ffi_uniffi.FfiConfig
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.HostTransport

/**
 * Every config field the SDK exposes. Each field lists its own default
 */
data class CoproductConfig(
    /**
     * Poll interval in seconds. Default 60. A 30-second minimum is enforced, and
     * a negative value is rejected at initialize
     */
    val pollIntervalSecs: Long = 60L,

    /**
     * Startup timeout in seconds. Default 3. The maximum time initialize waits
     * for the first poll before returning with the SDK polling in the
     * background. A slow or unreachable first poll never fails initialize: reads
     * serve cached values or supplied defaults until the first successful poll
     * lands
     */
    val startupTimeoutSecs: Long = 3L,

    /**
     * Override the auto-generated anonymous id, persisted over any prior value
     */
    val anonymousId: String? = null,

    /**
     * Custom edge endpoint. Defaults to the production Coproduct edge worker
     */
    val endpoint: String? = null,

    /**
     * Re-poll immediately when the app returns to foreground. Default true
     */
    val pollOnForeground: Boolean = true,

    /**
     * Per-request timeout in milliseconds applied by the platform transport.
     * Null means use the platform binding's native default. Callers override
     * this only when they have a specific reason such as slow networks or
     * long-running fixture servers
     */
    val requestTimeoutMs: Long? = null,

    /**
     * Override the default HttpURLConnection transport with a custom one
     * (useful for proxies, certificate pinning, or tests)
     */
    val transport: HostTransport? = null,

    /**
     * Override the default EncryptedSharedPreferences secure store (useful for
     * tests)
     */
    val secureStore: HostSecureStore? = null,
) {
    /**
     * Convert to the wire config the initialize FFI call accepts. Throws
     * [IllegalArgumentException] when [pollIntervalSecs] or [startupTimeoutSecs]
     * is negative. The Rust core's validate_config then enforces the business
     * range checks (for example a pollInterval below 30) on the resulting value
     */
    fun toFfiConfig(): FfiConfig =
        FfiConfig(
            pollIntervalSecs = safeULongSeconds(pollIntervalSecs, field = "pollIntervalSecs"),
            startupTimeoutSecs = safeULongSeconds(startupTimeoutSecs, field = "startupTimeoutSecs"),
            anonymousId = anonymousId,
            endpoint = endpoint,
            pollOnForeground = pollOnForeground,
        )
}

/**
 * Safely convert a count of seconds to a ULong for FFI. Throws
 * [IllegalArgumentException] on a negative value, which cannot be represented
 *
 * This mirrors the iOS wrapper's safeUInt64Seconds guard, which additionally
 * rejects NaN, infinities, and values too large to fit, because iOS takes
 * seconds as a floating-point TimeInterval. A Kotlin Long has no NaN or
 * infinite state, so those failure modes cannot occur here, and a
 * non-negative Long always fits in ULong, so there is no overflow case to
 * reject either. Negative is the one failure mode Long can actually produce
 */
internal fun safeULongSeconds(value: Long, field: String): ULong {
    require(value >= 0) { "$field must be a non-negative number of seconds, got $value" }
    return value.toULong()
}
