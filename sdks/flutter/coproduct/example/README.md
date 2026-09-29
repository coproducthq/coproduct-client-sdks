# Coproduct example

A small app showing how to initialize the SDK, read a flag, and observe changes
as values update.

## Running it

Copy `lib/main.dart` into a Flutter app that depends on `coproduct` from
pub.dev, then run it with your mobile SDK key:

```sh
flutter run --dart-define=COPRODUCT_SDK_KEY=your_mobile_sdk_key
```

That path uses the published prebuilt binaries and needs no Rust toolchain.

The key is read with `String.fromEnvironment`, so pass it with `--dart-define`
rather than editing the source. Without it the app runs with a placeholder key
that Coproduct rejects, and every flag serves its default.

Working in a clone of the repository? See
[DEVELOPMENT.md](https://github.com/coproducthq/coproduct-client-sdks/blob/main/DEVELOPMENT.md)
for building the example from source.

## Flags it reads

Create these flags in the project your key belongs to, or the app shows its
default values:

| Flag key | Flag type | Read with |
|---|---|---|
| `test-flag` | Boolean | `CoproductFlagBuilder.boolFlag` and `getBool` |
| `greeting` | String | `CoproductFlagBuilder.stringFlag` and `getString` |
| `max-items` | Number | `CoproductFlagBuilder.intFlag` and `getInt` |
| `ratio` | Number | `CoproductFlagBuilder.numberFlag` and `getNumber` |
| `theme` | JSON | `CoproductFlagBuilder.jsonFlag` and `getJson` |

## How it starts

This example initializes after `runApp` rather than before it, so the first
frame renders immediately and the app shell is visible while the SDK starts.
The package README's quick start does the opposite and awaits `initialize`
before `runApp`. The first frame then shows real values whenever the flags
arrive within `startupTimeout` or are saved from an earlier launch. Both
approaches are supported. Choose based on whether you would rather show the
app shell sooner or avoid a frame of default values.

See the package README for the full API.
