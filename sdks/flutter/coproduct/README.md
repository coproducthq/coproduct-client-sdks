# coproduct_flutter

Flutter SDK for the [Coproduct](https://coproduct.app) feature flag and experimentation platform. Wraps the shared Rust evaluation engine via [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge).

## Status

Pre-1.0. The customer-facing API is specified separately and not yet implemented at production polish. Do not adopt for production use until v1.0.

## Compatibility

| | Supported |
|---|---|
| Flutter | 3.x stable |
| Dart | 3.x |
| iOS deployment target | 15.0+ |
| Android minSdk | 24 |
| Gradle (Android side) | 9.x (cargokit Gradle 9 patch carried in our vendored cargokit) |

## Installation

```yaml
dependencies:
  coproduct_flutter: ^1.0.0
```

## Quickstart

```dart
import 'package:coproduct_flutter/coproduct_flutter.dart';

final client = await Coproduct.initialize(sdkKey: 'cpk_mob_...');
await client.identify(userId: 'alice');

if (client.getBool('new-checkout', defaultValue: false)) {
  showNewCheckoutFlow();
}
```

For reactive integration:

```dart
class CheckoutScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Coproduct.observe('new-checkout', defaultValue: false),
      builder: (context, value, _) => value ? NewCheckoutFlow() : OldCheckoutFlow(),
    );
  }
}
```

## Known compatibility notes

**Gradle 9 cargokit patch.** Upstream cargokit calls `project.exec()`, which was removed in Gradle 9. Our vendored cargokit at `cargokit/gradle/plugin.gradle` carries a `ProcessBuilder` patch ([FRB issue #3007](https://github.com/fzyzcjy/flutter_rust_bridge/issues/3007), wontfix upstream). The patch is transparent to Flutter customers but is documented here for completeness.

## Building from source

See the repo-root [DEVELOPMENT.md](../../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../../LICENSE). The vendored cargokit carries its own upstream license at `cargokit/LICENSE`.
