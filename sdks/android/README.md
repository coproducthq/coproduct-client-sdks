# Coproduct Android SDK

Kotlin SDK for the [Coproduct](https://coproduct.app) feature flag and experimentation platform. Wraps the shared Rust evaluation engine via UniFFI bindings.

## Status

Pre-1.0. The customer-facing API is specified separately and not yet implemented at production polish. Do not adopt for production use until v1.0.

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
import app.coproduct.Coproduct

val client = Coproduct.initialize(sdkKey = "cpk_mob_...")
client.identify(userId = "alice")

if (client.getBool("new-checkout", default = false)) {
    showNewCheckoutFlow()
}
```

For Jetpack Compose integration:

```kotlin
@Composable
fun CheckoutScreen() {
    val newCheckout by Coproduct.rememberFlag("new-checkout", default = false)
    if (newCheckout) NewCheckoutFlow() else OldCheckoutFlow()
}
```

## Known compatibility notes

None at v1.0.

## Building from source

See the repo-root [DEVELOPMENT.md](../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../LICENSE).
