package app.coproduct.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.result.ActivityResultCaller
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// The default requestPermission implementation, backed by a real Android
// runtime-permission prompt. Must be constructed once, synchronously,
// during CoproductOnboardingFlow's own setup -- androidx.activity's
// registerForActivityResult requires an unconditional, pre-STARTED
// registration call, so this class registers its single launcher in its
// constructor rather than lazily on first request. Because that launcher
// has exactly one registered callback for the lifetime of this instance,
// concurrent request() calls are serialized through requestMutex rather
// than allowed to race -- two overlapping requests sharing the launcher's
// single callback would otherwise let the second call's in-flight state
// silently overwrite the first's, delivering the wrong result to one
// caller and permanently hanging the other.
class DefaultPermissionRequester(caller: ActivityResultCaller) : PermissionRequestFn {
    private var pending: CompletableDeferred<Boolean>? = null
    private val requestMutex = Mutex()

    private val launcher = caller.registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> pending?.complete(granted); pending = null }

    override suspend fun request(permission: String): Map<String, String> {
        if (permission == "notifications") {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                return mapOf("status" to "granted")
            }
            return requestManifestPermission(Manifest.permission.POST_NOTIFICATIONS)
        }
        val manifestPermission = Permissions.manifestPermissionFor(permission)
            ?: return mapOf("status" to "error", "message" to "Unknown permission \"$permission\"")
        return requestManifestPermission(manifestPermission)
    }

    private suspend fun requestManifestPermission(manifestPermission: String): Map<String, String> =
        requestMutex.withLock {
            val deferred = CompletableDeferred<Boolean>()
            pending = deferred
            launcher.launch(manifestPermission)
            val granted = deferred.await()
            mapOf("status" to if (granted) "granted" else "denied")
        }
}
