# coproduct

Flutter SDK for the [Coproduct](https://coproduct.app) feature flag and experimentation platform. Wraps the shared Rust evaluation engine via [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge).

## Status

Pre-1.0. The public API is still being built out and is not yet at production polish. Do not adopt for production use until v1.0.

> **Pre-release.** The SDK fetches and evaluates real flags: it polls the
> Coproduct endpoint, applies automatic device and app context, serves
> targeted values from the synchronous getters, and observes flags reactively
> so a widget rebuilds when a value changes. A context-based client provider,
> a multi-flag API, and the detail getters are still to come before v1.0.

## Compatibility

| | Supported |
|---|---|
| Flutter | >= 3.38.1 |
| Dart | >= 3.10.0 |
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

## Reacting to flag changes

Read a flag once with the getters, or observe it and rebuild when it changes:

```dart
CoproductFlagBuilder.boolFlag(
  client: client,
  flagKey: 'new-checkout',
  defaultValue: false,
  builder: (context, enabled, child) =>
      enabled ? const NewCheckout() : const OldCheckout(),
)
```

For direct ownership, `client.observeBool('new-checkout', false)` returns a
`FlagObservation<bool>`, a `ValueListenable` you dispose when you are done with
it. Observations are also available for string, int, number, and JSON flags.

Ownership recipes for Provider, Riverpod, and BLoC, plus a zero-dependency way
to reach the client from deep in the widget tree, are in
[doc/state_management_recipes.md](doc/state_management_recipes.md).

## Known compatibility notes

**Gradle 9 cargokit patch.** Upstream cargokit calls `project.exec()`, which was removed in Gradle 9. Our vendored cargokit at `cargokit/gradle/plugin.gradle` carries a `ProcessBuilder` patch ([FRB issue #3007](https://github.com/fzyzcjy/flutter_rust_bridge/issues/3007), wontfix upstream). The patch is transparent to Flutter developers but is documented here for completeness.

## Building from source

See the repo-root [DEVELOPMENT.md](../../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../../LICENSE). The vendored cargokit carries its own upstream license at `cargokit/LICENSE`.
