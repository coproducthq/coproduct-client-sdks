# coproduct_example

A runnable sample for the `coproduct` Flutter SDK, source-linked to the plugin
in this repository so a change to the SDK is picked up without republishing.

## What it demonstrates

The app renders its shell immediately and initializes the SDK afterward, so
startup never waits on the network. Once `Coproduct.initialize` returns, the
client is installed in a `CoproductScope` and everything below it reads flags
without being handed the client.

Three things are worth reading in `lib/main.dart`:

- **`CoproductScope`** carries the client down the widget tree. Installing it
  once is what lets the widgets below omit `client:` entirely.
- **`CoproductFlagBuilder.boolFlag`** rebuilds its own subtree whenever the flag
  changes, and disposes its observation when it leaves the tree. Nothing in the
  app manages that lifetime.
- **`CoproductScope.of(context).getBool(...)`** reads the same flag once, when
  that widget builds. Placing it beside the builder shows the difference: the
  getter is a point-in-time read, the observation follows changes.

The README quickstart shows the other common shape, awaiting `initialize`
before `runApp`. Both are correct; this one keeps the first frame immediate.

## Running

From this directory, with a booted simulator or emulator:

```bash
cd sdks/flutter/coproduct/example
flutter run --dart-define=COPRODUCT_SDK_KEY=<your-mobile-sdk-key>
```

Add `-d <udid>` to choose a specific device.

To see a real value rather than the default, create a boolean flag with the key
`test-flag` in Coproduct, or change `test-flag` in `lib/main.dart` to a boolean
flag key you already have. Flags and SDK keys are created through the Coproduct
MCP app.

Running without `--dart-define` still works: the app falls back to a
well-formed placeholder key, so it starts and reports ready, but no flag data
ever arrives and both readings show the default. If you passed a real key and
still see the default, the flag key is the thing to check first.

The repository's build scripts compile this app on both platforms, so it also
serves as a compile check that the public API is usable as written. See
`DEVELOPMENT.md`.
