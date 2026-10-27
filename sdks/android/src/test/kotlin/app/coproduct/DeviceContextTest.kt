package app.coproduct

import android.content.res.Configuration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeviceContextTest {
    @Test
    fun deviceTypeMapsBySmallestScreenWidth() {
        val phone = Configuration().apply { smallestScreenWidthDp = 360 }
        val tablet = Configuration().apply { smallestScreenWidthDp = 600 }
        val undefined = Configuration().apply {
            smallestScreenWidthDp = Configuration.SMALLEST_SCREEN_WIDTH_DP_UNDEFINED
        }
        assertEquals("phone", DeviceContext.deviceType(phone))
        assertEquals("tablet", DeviceContext.deviceType(tablet))
        assertNull(DeviceContext.deviceType(undefined))
    }
}
