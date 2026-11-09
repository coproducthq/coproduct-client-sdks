package app.coproduct.onboarding

import android.Manifest
import android.os.Build

// Maps the authored flow's requestPermission action to a real Android
// runtime-permission string for camera/microphone/location/photos.
// "notifications" is handled separately by DefaultPermissionRequester, the
// same way RN's permissions.ts pulls it out of its PERMISSIONS table into
// its own requestNotifications() branch -- Android's notification
// permission (POST_NOTIFICATIONS) only exists from API 33, below which
// there is nothing to request. Mirrors Flutter's
// _defaultRequestPermission/_permissionByName (flow_runtime.dart) and RN's
// permissions.ts, both backed by a different permission library.
object Permissions {
    fun manifestPermissionFor(name: String): String? = when (name) {
        "camera" -> Manifest.permission.CAMERA
        "microphone" -> Manifest.permission.RECORD_AUDIO
        "location" -> Manifest.permission.ACCESS_FINE_LOCATION
        "photos" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        else -> null
    }
}

fun interface PermissionRequestFn {
    suspend fun request(permission: String): Map<String, String>
}
