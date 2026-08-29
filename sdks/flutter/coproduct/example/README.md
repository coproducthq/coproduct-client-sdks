# Coproduct example

A small app showing how to initialize the SDK, read a flag, and observe changes
as values update.

This example source-links the SDK, so it needs the native libraries built
first. They are gitignored build output and absent from a clean checkout:

```sh
scripts/package/flutter-build-native.sh all
```

Or use the source-linked demo scripts, which run that step for you:
`scripts/build/source-linked-flutter-demo-ios.sh` and
`...-android.sh`.

Then, from a checkout of this package:

```sh
flutter pub get
flutter run --dart-define=COPRODUCT_SDK_KEY=your_mobile_sdk_key
```

The key is read with `String.fromEnvironment`, so pass it with `--dart-define`
rather than editing the source. Without it the app runs against a placeholder
and every flag serves its caller default.

This example initializes after `runApp` rather than before it, so the first
frame renders immediately and the shell is visible while the SDK starts. The
package README's Quickstart does the opposite, awaiting `initialize` before
`runApp`, which keeps the first frame authoritative. Both are supported; choose
by whether you would rather show the shell sooner or avoid a frame of defaults.

See the package README for the full API.
