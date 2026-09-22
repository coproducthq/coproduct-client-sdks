package app.coproduct.flutter

import android.content.res.Configuration

/// Maps an Android device to the phone or tablet vocabulary, or to no value.
/// The 600dp threshold is the one Android's own sw600dp resource qualifier uses,
/// but this is Coproduct classification policy rather than a device fact the OS
/// reports, and it is documented as such.
///
/// Every decision lives here rather than in the plugin, so a unit test can reach
/// all of them: the plugin only extracts the two configuration values and hands
/// over the feature lookup.
internal object DeviceClassifier {
    private const val TABLET_MIN_WIDTH_DP = 600

    fun classify(
        uiModeType: Int,
        smallestScreenWidthDp: Int,
        hasFeature: (String) -> Boolean,
    ): String? {
        when (uiModeType) {
            // A docked phone is still a phone, and an undefined mode says
            // nothing that should override a valid width
            Configuration.UI_MODE_TYPE_NORMAL,
            Configuration.UI_MODE_TYPE_DESK,
            Configuration.UI_MODE_TYPE_UNDEFINED -> Unit
            Configuration.UI_MODE_TYPE_TELEVISION,
            Configuration.UI_MODE_TYPE_WATCH,
            Configuration.UI_MODE_TYPE_CAR,
            Configuration.UI_MODE_TYPE_APPLIANCE,
            Configuration.UI_MODE_TYPE_VR_HEADSET -> return null
            // A mode type added after this build. Fail closed rather than
            // forcing a device into a cohort it may not belong to
            else -> return null
        }
        // ChromeOS and Android PC devices are excluded rather than reported as
        // tablets, so the attribute selects the same population it selects on
        // iOS, which omits the Mac idiom
        if (hasFeature("android.hardware.type.pc") || hasFeature("org.chromium.arc")) {
            return null
        }
        if (smallestScreenWidthDp <= 0) return null
        return if (smallestScreenWidthDp >= TABLET_MIN_WIDTH_DP) "tablet" else "phone"
    }
}
