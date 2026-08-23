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
flutter run
```

Replace the placeholder SDK key in `lib/main.dart` with a key from your
Coproduct project. See the package README for the full API.
