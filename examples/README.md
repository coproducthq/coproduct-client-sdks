# Examples

Source-linked sample apps for SDK author development. Each app pulls the SDK as workspace code, so iteration is fast and changes to SDK source flow into the example without a publish step.

These are the inner-loop developer experience surfaces. They are NOT the release gate. For release-shaped verification, see [`consumer-tests/`](../consumer-tests/).

## Available examples

| Platform | Directory | Source-linked via |
|---|---|---|
| Native iOS | [ios-demo/](./ios-demo/) | Swift Package Manager local reference |
| Native Android | [android-demo/](./android-demo/) | Gradle composite build |
| React Native | [../sdks/react-native/coproduct/example/](../sdks/react-native/coproduct/example/) | React Native autolinking (nested because bob requires it) |
| Flutter | [../sdks/flutter/coproduct/example/](../sdks/flutter/coproduct/example/) | Flutter plugin `path:` reference (nested because `flutter create --template=plugin` requires it) |

## Why two patterns

The `examples/` directory is the natural location for sample apps, but the React Native and Flutter packaging tools (`bob` for RN, `flutter create --template=plugin` for Flutter) require sample apps to live inside the SDK package directory. They are documented here for navigation, with the actual code at the nested paths.

## Build commands

See [DEVELOPMENT.md](../DEVELOPMENT.md) at the repository root for prerequisites and the exact build invocations.
