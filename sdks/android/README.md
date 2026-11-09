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
