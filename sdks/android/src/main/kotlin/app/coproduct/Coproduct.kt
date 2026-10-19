package app.coproduct

import android.content.Context
import uniffi.coproduct_ffi_uniffi.FfiConfig
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.initialize

object Coproduct {
    // User agent identifying this platform wrapper to the Coproduct backend
    private const val USER_AGENT = "coproduct-android/0.0.1-dev"

    // Future public initializer shape once host Transport / SecureStore
    // interfaces are exposed by the Android wrapper.
    //
    // suspend fun initialize(
    //     sdkKey: String,
    //     context: Context,
    //     transport: HostTransport,
    //     secureStore: HostSecureStore,
    // ): CoproductClient { ... }

    suspend fun initialize(sdkKey: String, context: Context): CoproductClient {
        val cacheDir = context.cacheDir.absolutePath
        val nativeClient = initialize(
            sdkKey = sdkKey,
            userAgent = USER_AGENT,
            cacheDir = cacheDir,
            config = FfiConfig(
                pollIntervalSecs = 60u,
                startupTimeoutSecs = 3u,
                anonymousId = null,
                endpoint = null,
                pollOnForeground = true,
            ),
            transport = AndroidHostTransport,
            secureStore = AndroidHostSecureStore,
        )
        return CoproductClient(nativeClient)
    }
}
