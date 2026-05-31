# Coproduct iOS SDK

Swift SDK for the [Coproduct](https://coproduct.app) feature flag and experimentation platform. Wraps the shared Rust evaluation engine via UniFFI bindings.

## Status

Pre-1.0. The customer-facing API is specified separately and not yet implemented at production polish. Do not adopt for production use until v1.0.

## Compatibility

| | Supported |
|---|---|
| iOS | 15.0+ |
| Swift | 5.0+ |
| Xcode | 16.0+ |
| Package manager | Swift Package Manager |

## Installation

Add as a dependency in your `Package.swift`:

```swift
.package(url: "https://github.com/coproducthq/coproduct-ios.git", from: "1.0.0")
```

Then import:

```swift
import Coproduct
```

## Quickstart

```swift
import Coproduct

let client = try await Coproduct.initialize(sdkKey: "cpk_mob_...")
client.identify(userId: "alice")

if client.getBool("new-checkout", default: false) {
    showNewCheckoutFlow()
}
```

For SwiftUI integration with reactive flag values:

```swift
struct CheckoutView: View {
    @CoproductFlag("new-checkout", default: false) var newCheckout: Bool
    var body: some View {
        newCheckout ? NewCheckoutFlow() : OldCheckoutFlow()
    }
}
```

## Known compatibility notes

None at v1.0.

## Building from source

See the repo-root [DEVELOPMENT.md](../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../LICENSE).
