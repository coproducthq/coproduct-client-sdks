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

```bash
flutter run                 # picks the booted device
flutter run -d <udid>       # or target one
```

Without `--dart-define=COPRODUCT_SDK_KEY=<key>` the app falls back to a
well-formed placeholder key, so `initialize` succeeds and the SDK reports
ready, but no snapshot ever arrives and both readings show the caller default.
That is the expected result: this sample exists to show the shape of the API,
not to serve live values.

The repository's build scripts compile this app on both platforms, so it also
serves as a compile check that the public API is usable as written. See
`DEVELOPMENT.md`.
