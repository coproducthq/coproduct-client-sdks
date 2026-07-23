# coproduct

Flutter SDK for the [Coproduct](https://coproduct.app) feature flag and experimentation platform. Wraps the shared Rust evaluation engine via [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge).

## Status

Pre-1.0. The public API is still being built out and is not yet at production polish. Do not adopt for production use until v1.0.

> **Not yet functional.** This preview does not fetch flags: there is no network fetch or polling yet, so the getters return cached or default values. The Quickstart below is an API-shape preview of how the SDK is used; real targeted values arrive once the host runtime (transport plus polling) lands.

## Compatibility

| | Supported |
|---|---|
| Flutter | 3.x stable |
| Dart | 3.x |
| iOS deployment target | 15.0+ |
| Android minSdk | 24 |
| Gradle (Android side) | 9.x (cargokit Gradle 9 patch carried in our vendored cargokit) |

## Installation

> The SDK is not yet published to pub.dev. Once it is released, add it to your
> `pubspec.yaml` (the published version is set at release):

```yaml
dependencies:
  coproduct: <released-version>
```

## Quickstart

```dart
import 'package:coproduct/coproduct.dart';

final client = await Coproduct.initialize(sdkKey: 'cpk_mob_...');

await client.identify(userId: 'alice', attributes: {
  'plan': const AttributeValue.string('pro'),
});

if (client.getBool('new-checkout', false)) {
  showNewCheckoutFlow();
}
```

## Known compatibility notes

**Gradle 9 cargokit patch.** Upstream cargokit calls `project.exec()`, which was removed in Gradle 9. Our vendored cargokit at `cargokit/gradle/plugin.gradle` carries a `ProcessBuilder` patch ([FRB issue #3007](https://github.com/fzyzcjy/flutter_rust_bridge/issues/3007), wontfix upstream). The patch is transparent to Flutter developers but is documented here for completeness.

## Building from source

See the repo-root [DEVELOPMENT.md](../../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../../LICENSE). The vendored cargokit carries its own upstream license at `cargokit/LICENSE`.
