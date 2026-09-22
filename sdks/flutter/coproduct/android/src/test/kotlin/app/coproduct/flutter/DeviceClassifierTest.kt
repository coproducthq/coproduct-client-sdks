package app.coproduct.flutter

import android.content.res.Configuration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeviceClassifierTest {
    @Test fun phoneBelowThreshold() =
        assertEquals("phone", classify(Configuration.UI_MODE_TYPE_NORMAL, 411))

    @Test fun tabletAtThreshold() =
        assertEquals("tablet", classify(Configuration.UI_MODE_TYPE_NORMAL, 600))

    @Test fun tabletAboveThreshold() =
        assertEquals("tablet", classify(Configuration.UI_MODE_TYPE_NORMAL, 800))

    @Test fun deskModeStillClassifies() =
        assertEquals("phone", classify(Configuration.UI_MODE_TYPE_DESK, 411))

    @Test fun undefinedModeStillClassifies() =
        assertEquals("tablet", classify(Configuration.UI_MODE_TYPE_UNDEFINED, 800))

    @Test fun televisionOmits() =
        assertNull(classify(Configuration.UI_MODE_TYPE_TELEVISION, 960))

    @Test fun watchOmits() =
        assertNull(classify(Configuration.UI_MODE_TYPE_WATCH, 200))

    @Test fun carOmits() =
        assertNull(classify(Configuration.UI_MODE_TYPE_CAR, 800))

    @Test fun applianceOmits() =
        assertNull(classify(Configuration.UI_MODE_TYPE_APPLIANCE, 400))

    @Test fun vrHeadsetOmits() =
        assertNull(classify(Configuration.UI_MODE_TYPE_VR_HEADSET, 800))

    @Test fun unknownFutureModeOmits() = assertNull(classify(99, 800))

    @Test fun undefinedWidthOmits() =
        assertNull(classify(Configuration.UI_MODE_TYPE_NORMAL, 0))

    @Test fun negativeWidthOmits() =
        assertNull(classify(Configuration.UI_MODE_TYPE_NORMAL, -1))

    // The feature names are the contract, so a test pins them rather than
    // leaving them to hardware the suite never runs on
    @Test fun pcFeatureOmits() = assertNull(
        DeviceClassifier.classify(Configuration.UI_MODE_TYPE_NORMAL, 1280) {
            it == "android.hardware.type.pc"
        }
    )

    @Test fun chromeOsMarkerOmits() = assertNull(
        DeviceClassifier.classify(Configuration.UI_MODE_TYPE_NORMAL, 1280) {
            it == "org.chromium.arc"
        }
    )

    @Test fun anUnrelatedFeatureDoesNotOmit() = assertEquals(
        "tablet",
        DeviceClassifier.classify(Configuration.UI_MODE_TYPE_NORMAL, 1280) {
            it == "android.hardware.camera"
        }
    )

    private fun classify(uiMode: Int, width: Int) =
        DeviceClassifier.classify(uiMode, width) { false }
}
