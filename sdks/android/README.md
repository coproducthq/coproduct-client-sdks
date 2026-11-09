# Coproduct Android SDK

Kotlin SDK for the [Coproduct](https://coproduct.app) feature flag and experimentation platform. Wraps the shared Rust evaluation engine via UniFFI bindings.

## Status

Pre-1.0. Flags are at production parity with the iOS SDK: typed getters,
identity, per-type observation, host-driven polling, automatic attributes,
and production transport/secure-store defaults. Onboarding and paywall are
not yet implemented. Do not adopt for production use until v1.0.

## Compatibility

| | Supported |
|---|---|
| Android minSdk | 24 (Android 7.0) |
| Android compileSdk | 36 |
| Kotlin | 2.2+ |
| Gradle | 8.14+ |
| JDK | 17 |

## Installation

```kotlin
dependencies {
    implementation("app.coproduct:coproduct-android:1.0.0")
}
```

## Quickstart

```kotlin
import app.coproduct.AttributeValue
import app.coproduct.Coproduct

val client = Coproduct.initialize(sdkKey = "cpk_mob_...", context = applicationContext)
client.identify(userId = "alice")

if (client.getBool("new-checkout", default = false)) {
    showNewCheckoutFlow()
}

val cancellable = client.observeBool("new-checkout", default = false) { enabled ->
    // called once immediately with the current value, then on every change
}
// cancellable.cancel() when the observer is no longer needed
```

For Jetpack Compose integration:

```kotlin
import app.coproduct.compose.rememberBoolFlag

@Composable
fun CheckoutScreen(client: CoproductClient) {
    val newCheckout by client.rememberBoolFlag("new-checkout", default = false)
    if (newCheckout) NewCheckoutFlow() else OldCheckoutFlow()
}
```

## Campaign attribution (UTM)

Target users by the campaign that brought them to your app. The SDK saves UTM parameters on the device and sets these attributes for your rules:

| URL parameter | First-touch attribute | Last-touch attribute |
|---|---|---|
| `utm_source` | `utm_source` | `utm_source_last` |
| `utm_medium` | `utm_medium` | `utm_medium_last` |
| `utm_campaign` | `utm_campaign` | `utm_campaign_last` |
| `utm_term` | `utm_term` | `utm_term_last` |
| `utm_content` | `utm_content` | `utm_content_last` |

- **First-touch** is the first value captured for that parameter. It never changes after that.
- **Last-touch** is the most recent value captured for that parameter.

**Install referrer:** the SDK reads the Google Play install referrer automatically during `initialize`.

**Deep links:** the SDK does not listen for links, so pass them to `captureAttribution`. Your app needs a deep-link intent filter.

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) captureLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureLink(intent)
    }

    private fun captureLink(intent: Intent) {
        intent.data?.let { Coproduct.captureAttribution(this, it.toString()) }
    }
}
```

`Coproduct.captureAttribution(context, url)` can be called before `initialize`. The values are saved and apply when `initialize` runs. With a client, you can also call `client.captureAttribution(url)`.

- **Each parameter is tracked on its own.** A link with only `utm_source` leaves the other saved values alone, so one device's values can come from different links.
- **Links without UTM parameters change nothing.** Other query parameters and empty values are ignored, and capturing the same link twice is harmless.
- **Values are kept as they appear in the link**, after URL decoding. Each attribute is a string, and is unset until a link supplies it, so a rule that needs a value does not match.
- **Rules update as soon as a link is captured**, and saved values apply again at every `initialize`.
- **Values belong to the device, not the signed-in user.** `identify`, `setContext`, and `signOut` never change them, and every account on the device shares them.
- **An attribute you set with the same name takes precedence** while it is set.
- **Values stay on the device.** They are never sent to Coproduct.
- **First-touch is not tied to the install.** It is the first link captured, which can be long after the app was installed.
- **The install referrer is read at every `initialize`.** When Google Play returns UTM parameters, they overwrite last-touch on each launch, replacing values from a deep link. First-touch is not affected. Organic installs can report values such as `utm_source=google-play`.
- **Reinstalling can reset the values.** Uninstalling removes them unless Android Auto Backup restores your app's data, and the next value captured becomes the new first-touch.
- **Permission:** the Play Install Referrer library adds `com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE` to your app's manifest. It needs no prompt.

## Segmentation by GPS location (geo-fencing)

Target a flag or segment by a **geo-fence**: a center latitude/longitude and a radius. The flag turns on when the device is physically inside that circle. Matching runs on-device, so the raw coordinates never leave the phone.

Author the fence in the dashboard: add a **Location (GPS)** condition with the **within radius of** operator to a segment, set the center and radius, and point your flag's targeting rule at that segment. The SDK's job is to supply the device position as the `device_location` attribute.

Location is opt-in. The SDK never touches location at `initialize`.

```kotlin
// Start supplying device_location. Returns false if the location permission
// has not been granted (see the permission note below).
val enabled = Coproduct.enableLocation()

// Optional: refresh on a foreground interval, in milliseconds.
// Default 2 minutes, 30s floor, 0 = a single fix with no repeating loop.
Coproduct.setLocationUpdateInterval(milliseconds = 120_000L)

// Force a one-off refresh.
Coproduct.refreshLocation()
```

**Permission is the host app's responsibility on Android.** Unlike iOS, the native Android SDK does not and cannot show the runtime permission dialog: it reads location through the platform `LocationManager` from an application context, and only an `Activity` can present that prompt. Declare `ACCESS_FINE_LOCATION` (or `ACCESS_COARSE_LOCATION`) in your manifest and request it at runtime yourself before calling `enableLocation()`. If it is not granted, `enableLocation()` returns `false` and `device_location` stays unset.

Inside/outside is delivered through the flag you already observe (`observeBool` / `rememberBoolFlag`); there is no separate geo-fence callback. If permission is denied or location is off, geo-fence rules fall through to the flag's default variation.

## Known compatibility notes

None at v1.0.

## Building from source

See the repo-root [DEVELOPMENT.md](../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../LICENSE).
