package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [DeviceContext.staticAttributes] itself is Android-framework-bound
 * (PackageManager, Resources, Build) and needs instrumentation to exercise,
 * but the device_type threshold it applies is a pure function of
 * smallestScreenWidthDp and is unit-tested directly here
 */
class DeviceContextTest {
    @Test
    fun phoneBelowThreshold() {
        assertEquals("phone", DeviceContext.deviceTypeForWidth(411))
    }

    @Test
    fun tabletAtThreshold() {
        assertEquals("tablet", DeviceContext.deviceTypeForWidth(600))
    }

    @Test
    fun tabletAboveThreshold() {
        assertEquals("tablet", DeviceContext.deviceTypeForWidth(800))
    }

    @Test
    fun undefinedWidthOmits() {
        assertNull(DeviceContext.deviceTypeForWidth(0))
    }

    @Test
    fun negativeWidthOmits() {
        assertNull(DeviceContext.deviceTypeForWidth(-1))
    }
}
