# Coproduct example

A small app showing how to initialize the SDK, read a flag, and observe changes
as values update.

**Reading this on pub.dev?** Copy `lib/main.dart` into an app that depends on
`coproduct` from pub.dev and run it with the `--dart-define` below. That path
uses the published prebuilt binaries and needs no Rust toolchain.

**Working in a clone of the repository?** This example source-links the SDK and
compiles the Rust core, so it needs Rust, Xcode, and the Android NDK. Build the
native libraries first — they are gitignored build output, absent from a clean
checkout:

```sh
scripts/package/flutter-build-native.sh all
```

The source-linked demo scripts run that step for you:
`scripts/build/source-linked-flutter-demo-ios.sh` and
`scripts/build/source-linked-flutter-demo-android.sh`.

Then, from this directory:

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
