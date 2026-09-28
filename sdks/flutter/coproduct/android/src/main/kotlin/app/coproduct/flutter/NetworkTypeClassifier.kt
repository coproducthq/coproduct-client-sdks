package app.coproduct.flutter

import android.net.NetworkCapabilities

/**
 * Maps a connected default network to the network_type vocabulary, with the
 * precedence the iOS SDK uses so one physical network maps the same way on
 * both. A VPN is not a transport of its own here: from Android 9 its
 * capabilities usually also carry the transports beneath it, which this sees,
 * and a VPN that names none of the three falls through to other with
 * everything else. No default network at all is decided by the observer, not here
 */
internal object NetworkTypeClassifier {
    fun classify(hasTransport: (Int) -> Boolean): String = when {
        hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
        hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
        hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
        // Connected through something else, which is not offline
        else -> "other"
    }
}
