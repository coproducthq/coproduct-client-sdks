package app.coproduct.flutter

import android.net.NetworkCapabilities
import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkTypeClassifierTest {
    private fun classify(vararg transports: Int) =
        NetworkTypeClassifier.classify { it in transports }

    @Test fun eachKnownTransportMapsToItsValue() {
        assertEquals("wifi", classify(NetworkCapabilities.TRANSPORT_WIFI))
        assertEquals("cellular", classify(NetworkCapabilities.TRANSPORT_CELLULAR))
        assertEquals("ethernet", classify(NetworkCapabilities.TRANSPORT_ETHERNET))
    }

    @Test fun precedenceIsWifiThenCellularThenEthernet() {
        // The iOS SDK's order, so one physical network maps the same way on both
        assertEquals("wifi", classify(
            NetworkCapabilities.TRANSPORT_ETHERNET,
            NetworkCapabilities.TRANSPORT_CELLULAR,
            NetworkCapabilities.TRANSPORT_WIFI,
        ))
        assertEquals("cellular", classify(
            NetworkCapabilities.TRANSPORT_ETHERNET,
            NetworkCapabilities.TRANSPORT_CELLULAR,
        ))
    }

    @Test fun aVpnMapsToTheTransportBeneathIt() {
        // From Android 9 a VPN's capabilities usually carry the transports it
        // runs over, though not when the VPN declares it has none
        assertEquals("wifi", classify(NetworkCapabilities.TRANSPORT_VPN, NetworkCapabilities.TRANSPORT_WIFI))
        assertEquals("cellular", classify(NetworkCapabilities.TRANSPORT_VPN, NetworkCapabilities.TRANSPORT_CELLULAR))
    }

    @Test fun aVpnNamingNoKnownTransportIsOther() {
        // Every VPN on Android 7.0 through 8.1, which reports only TRANSPORT_VPN
        assertEquals("other", classify(NetworkCapabilities.TRANSPORT_VPN))
    }

    @Test fun anyOtherConnectedTransportIsOtherNeverNone() {
        assertEquals("other", classify(NetworkCapabilities.TRANSPORT_BLUETOOTH))
        assertEquals("other", classify(NetworkCapabilities.TRANSPORT_USB))
        assertEquals("other", classify(NetworkCapabilities.TRANSPORT_LOWPAN))
        assertEquals("other", classify(NetworkCapabilities.TRANSPORT_SATELLITE))
        // A transport constant this build does not know
        assertEquals("other", classify(99))
        // Connected, with no transport reported at all
        assertEquals("other", classify())
    }
}
