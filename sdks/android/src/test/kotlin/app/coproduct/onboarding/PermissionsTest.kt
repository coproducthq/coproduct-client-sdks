package app.coproduct.onboarding

import android.Manifest
import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
class PermissionsTest {
    @Test
    fun mapsCameraMicrophoneAndLocation() {
        assertEquals(Manifest.permission.CAMERA, Permissions.manifestPermissionFor("camera"))
        assertEquals(Manifest.permission.RECORD_AUDIO, Permissions.manifestPermissionFor("microphone"))
        assertEquals(Manifest.permission.ACCESS_FINE_LOCATION, Permissions.manifestPermissionFor("location"))
    }

    @Test
    fun returnsNullForAnUnknownPermissionName() {
        assertNull(Permissions.manifestPermissionFor("explode"))
    }

    @Test
    @Config(sdk = [33])
    fun mapsPhotosToReadMediaImagesOnApi33Plus() {
        assertEquals(Manifest.permission.READ_MEDIA_IMAGES, Permissions.manifestPermissionFor("photos"))
    }

    @Test
    @Config(sdk = [28])
    fun mapsPhotosToReadExternalStorageBelowApi33() {
        assertEquals(Manifest.permission.READ_EXTERNAL_STORAGE, Permissions.manifestPermissionFor("photos"))
    }
}
