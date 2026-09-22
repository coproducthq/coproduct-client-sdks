# coproduct

Flutter SDK for [Coproduct](https://coproduct.app), a feature flag and
experimentation platform.

**This release covers feature flags:** delivery, targeting, identity, reactive
reads, and a testing library. Experiment tracking, recording which variant each
user saw, arrives in a following release.

A **feature flag** is a value you control from Coproduct rather than from your
app's code: a switch that turns a feature on or off, or a piece of
configuration you can change without shipping a release.

Flags do not have to be the same for everybody. In Coproduct you attach
targeting rules to a flag, and those rules match on **attributes** describing
the person using your app. That is how one flag serves `true` to the segment you
choose and `false` to everyone else, or serves a different limit to trial
accounts than to paid ones.

How that evaluation works, and which attributes you get for free, is in
[How evaluation works](#how-evaluation-works) below, after you have a flag
working.

## Compatibility

| | Supported |
|---|---|
| Flutter | >= 3.38.1 |
| Dart | >= 3.10.0 |
| iOS deployment target | 15.0+ |
| Android minSdk | 24 |
| Gradle (Android side) | 8.x or later |

## Before you start

You need two things from Coproduct before any of the code below returns a real
value:

- **A mobile SDK key.** It looks like `cpk_mob_` followed by thirty-two
  characters, and it tells the SDK which flags to download.
- **A flag.** A **flag key** is the stable string your code uses to ask for one
  flag, like `new-checkout`. The examples below use a boolean flag with that
  key, so create one to follow along, or substitute a key you already have.

Create both at [coproduct.app](https://coproduct.app):

1. Sign in and open the project you want the app to read flags from, or create
   one.
2. Issue a **mobile** SDK key for that project. Mobile keys are the only kind
   this SDK accepts; a server key is rejected at `initialize` with
   `InvalidKeyType`.
3. Create a boolean flag with the key `new-checkout`, or substitute a flag key
   you already have in the examples below.

If your team drives Coproduct through the Coproduct MCP app, you can ask it to
issue the key and create the flag instead. Either path produces the same two
values.

**Every read is safe.** Whatever happens, you get back a usable value: if the
key does not exist, or names a flag of a different type, or nothing has
downloaded yet, the SDK serves the default you passed. Reads never throw, so a
mistyped key or an outage degrades to your default rather than breaking a build
method.

The trade-off is that a wrong key looks exactly like a flag that is switched
off. If a flag seems stuck on its default, check the spelling and the
environment of your SDK key before looking anywhere else.

## Requirements

The SDK ships prebuilt native libraries, so **no Rust toolchain is required** to
build an app that depends on it.

**The iOS simulator slice is universal**, covering both Apple Silicon and Intel
Macs, and the SDK constrains no architectures in your project.

Supported toolchains are Flutter 3.38.1 and later, with a minimum iOS deployment
target of 15.0 and a minimum Android SDK of 24.

**Initialize from your app's main isolate.** A spawned background isolate cannot
receive the platform messages the SDK relies on, so `initialize` rejects one with
`CoproductUnsupportedIsolate`. This is about Dart isolates, not app lifecycle: an
app running in the background is fine, and each `FlutterEngine` has its own root
isolate, so multiple engines are supported.

## Installation

Add it to your `pubspec.yaml`:

```yaml
dependencies:
  coproduct: ^1.0.0
```

Set the platform minimums before your first build, or `pod install` refuses the
pod and the Android build fails:

- **iOS.** In `ios/Podfile`, set `platform :ios, '15.0'` at the top. A new
  Flutter app ships that line commented out, so uncomment it. Set the iOS
  Deployment Target to 15.0 in Xcode too, then run `pod install`.
- **Android.** In `android/app/build.gradle.kts`, set `minSdk = 24`.

## Quickstart

Start the SDK once, before your app runs, and put the client where your widgets
can find it. This is a complete `main`.

Replace the placeholder key before running it. `initialize` throws a
`CoproductException` for a malformed key or an invalid configuration, so a
copied-and-unedited placeholder fails immediately rather than silently serving
defaults.

```dart
import 'package:coproduct/coproduct.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  // Required before initialize, which reads the app version and cache
  // directory through platform plugins
  WidgetsFlutterBinding.ensureInitialized();

  final client = await Coproduct.initialize(sdkKey: 'cpk_mob_...');

  // CoproductScope makes the client available to every widget below it, so
  // nothing has to pass it down through constructors
  runApp(CoproductScope(client: client, child: const MyApp()));
}
```

`initialize` waits briefly for your flags to arrive, up to `startupTimeout`,
then returns whether or not they did. A slow or unreachable network delays
startup by at most that budget instead of failing it, and downloads continue in
the background. Reads before the flags arrive return the defaults you pass.

## Which read API should I use?

There are three ways to read a flag. Pick by what you are doing:

| What you are doing | Use |
|---|---|
| Building UI that should change when the flag changes | **`CoproductFlagBuilder`**, the right choice for most flag-gated widgets. One entry point per type: `boolFlag`, `stringFlag`, `intFlag`, `numberFlag`, `jsonFlag` |
| Reading the current value once, in logic outside the widget tree | **The getters**: `getBool`, `getString`, `getInt`, `getNumber`, `getJson` |
| Holding a value in your own `State`, or in Provider, Riverpod, or BLoC | **The observations**: `observeBool`, `observeString`, `observeInt`, `observeNumber`, `observeJson` |

**Calling `getBool` inside `build` does not make your widget rebuild when the
flag changes.** It reads the value at that moment and nothing more. If the flag
flips while your screen is open, the screen keeps showing the old value until
something else rebuilds it. That is the single mistake worth avoiding, and it is
why the builder is the default recommendation for UI.

## Your first flag-gated widget

`CoproductFlagBuilder` reads the flag, rebuilds when it changes, and cleans up
after itself. Drop it anywhere below the `CoproductScope` you installed in
`main`:

```dart
class CheckoutPage extends StatelessWidget {
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CoproductFlagBuilder.boolFlag(
      flagKey: 'new-checkout',
      defaultValue: false,
      builder: (context, enabled, child) =>
          enabled ? const NewCheckout() : const OldCheckout(),
    );
  }
}
```

`NewCheckout` and `OldCheckout` stand in for the two widgets from your app.

There is no `client` argument. The builder finds it in the scope above it. Until
your flags arrive, `enabled` is the `defaultValue` you passed, so the widget
always has something sensible to render.

That is the whole integration. Everything below is reference.

One thing to expect before you go looking for a bug: flipping the flag in
Coproduct does not change your running app straight away, because the SDK checks
for updates on a timer. See
[Seeing a flag change while you develop](#seeing-a-flag-change-while-you-develop)
for the quickest way to force it.

## How evaluation works

**Flags are evaluated on the device, not on a server.** The SDK downloads your
flag definitions and their targeting rules once, then works out which value
applies using attributes you set locally with `identify`. Reading a flag is a
synchronous in-memory lookup: it makes no network request, so it never blocks a
build and never fails because the network is down. The attributes you set stay
on the device unless you send them somewhere yourself.

Attributes come from two places:

- **The SDK fills in seven automatically**, with no code from you: `platform`,
  `os_version`, `app_version`, `app_build`, `locale`, `timezone`, and
  `device_type`. So you can target Android only, or a locale, or tablets, or
  roll a feature out to builds at or above a version, straight away.

  `device_type` is `"phone"` or `"tablet"`, and is **left unset rather than
  guessed** on a device that is neither. On iOS it comes from the interface
  idiom the system reports, so a Mac, an Apple TV, CarPlay, or Vision device has
  no value. On Android there is no equivalent property, so Coproduct classifies
  by the 600dp width Android's own `sw600dp` layout qualifier uses: this is our
  policy rather than something the OS tells us. Televisions, watches, cars,
  appliances, VR headsets, Chromebooks and Android PCs are left unset. A
  foldable is classified from its posture when the SDK starts and is not
  reclassified when it folds, so write rules that tolerate either value if that
  matters to you.

  Most of these are ready the moment `initialize` returns. One whose source is
  slow can arrive shortly after instead, and an observation re-emits when it
  does, so prefer `CoproductFlagBuilder` or an observation over a single read
  taken immediately after `initialize` if a rule depends on one of them.

- **You supply the rest**, through [`identify`](#identity). These are whatever
  your product needs a rule to match on, such as `plan`, `region`, or
  `signup_date`. Their names are yours, and they have to match the names your
  targeting rules use.

The two sets are kept apart, so supplying your own attributes never disturbs the
automatic ones.

## Reading flags

Five getters over four flag types. `getBool`, `getString`, `getNumber`, and
`getJson` map one to one; `getInt` reads a **number** flag and truncates toward
zero, so create a number flag when your code calls `getInt`. Each takes the flag
key and the value to serve
when the flag cannot be resolved. Reach the client from a widget with
`CoproductScope.of(context)`, or keep the one `initialize` returned:

```dart
final client = CoproductScope.of(context);

client.getBool('new-checkout', defaultValue: false);
client.getString('greeting', defaultValue: 'Hello');
client.getInt('max-items', defaultValue: 10);
client.getNumber('rollout-ratio', defaultValue: 0.0);
client.getJson('checkout-config', defaultValue: const {'maxItems': 10});
```

Reads never throw. Your default is served whenever the flag is missing, the SDK
has not downloaded anything yet, or the stored value is not the type you asked
for, so a read is safe at any point in your app's life, including after
`shutdown`.

Two type details worth knowing. Integers travel as the numeric flag type, so
`getInt` truncates a fractional value toward zero and serves your default for a
value outside the signed 64-bit range. `getJson` returns a native Dart value, a
map, list, scalar, or null, and its default must be JSON-encodable; if encoding
or decoding fails, your default comes back unchanged rather than raising.

## Reacting to flag changes

`CoproductFlagBuilder` has an entry point per type, all shaped like the boolean
one above: `boolFlag`, `stringFlag`, `intFlag`, `numberFlag`, and `jsonFlag`.

When you want the value outside a builder, observe it directly:

```dart
final greeting = client.observeString('greeting', defaultValue: 'Hello');

greeting.value;                  // the current value, available immediately
greeting.addListener(_onChange); // called whenever it changes
greeting.dispose();              // required when you are done
```

A `FlagObservation<T>` is a `ValueListenable<T>`, so it works with
`ValueListenableBuilder` and with the state-management packages you already use.
**You must call `dispose()`**; the builder does that for you, which is why it is
the easier path.

## Using it with Provider, Riverpod, or BLoC

The SDK adds no state management dependency and does not ask you to adopt one.
`FlagObservation<T>` is a `ValueListenable<T>`, which all three of these
packages already know how to hold, so nothing needs adapting.

Two rules cover the integration:

**Getting the client there.** If your app already keeps the client in a
Provider, a Riverpod provider, or a BLoC repository, read it from there and pass
it as `client:`. You do not need `CoproductScope` as well. Use the scope when
you have nowhere else to put the client.

**Disposal.** Whoever creates an observation disposes it. Provider's `dispose:`
callback, Riverpod's `ref.onDispose`, and a Cubit's `close()` are each the right
place. `CoproductFlagBuilder` disposes its own, which is why it needs nothing
from you.

Worked examples for all three, plus one that uses no package at all, are in
[doc/state_management_recipes.md](doc/state_management_recipes.md).

## Identity

By default, flags are evaluated for an anonymous person. Tell Coproduct who is
using the app and your flags can target them:

```dart
await client.identify(
  userId: account.id,                                    // your stable account id
  attributes: {'plan': const AttributeValue.string('pro')},
);
```

**Attributes are what your targeting rules match against.** A rule configured in
Coproduct like "plan is pro" matches the attribute you send here, so the names
and values must line up with the rules on your flags.

Call this after your app knows who is signed in, not during startup. None of the
identity calls makes a network request: each re-evaluates the flags already
downloaded, so values update immediately. That is only true of identity. Editing
a flag in Coproduct changes the definitions themselves, which the SDK has to
download before it can see them, so those changes are not immediate. See
[Seeing a flag change while you develop](#seeing-a-flag-change-while-you-develop).

**Identity is not saved between launches.** Call `identify` again after
`initialize` every time your app starts, or your flags evaluate anonymously.

The other calls:

```dart
await client.updateAttributes({'seats': const AttributeValue.number(5)});
await client.removeAttributes(['seats']);
await client.signOut();
```

`identify` **replaces** the attributes, so anything absent from the map is
cleared. `updateAttributes` **merges**, leaving omitted keys alone.
`removeAttributes` drops the named ones. `signOut` returns to the anonymous
identity and clears attributes.

`setContext(targetingKey: ...)` sets the same identity as `identify` but takes
the targeting key directly and performs no anonymous-session linking. Reach for
it when what you target is not a signed-in account, such as a team or a device.

Two rules to remember. `identify` and `setContext` throw `InvalidTargetingKey`
if you pass an empty identifier. The names `user_id` and `targetingKey` are
reserved and ignored inside an attribute map, so set identity through the
parameter instead.

Awaiting these calls lets you see their errors. If you ignore the returned
future and the call fails, the error surfaces as an unhandled asynchronous
error instead.

### Advanced: linking an anonymous session

`client.previousAnonymousId` returns the anonymous id captured when someone
signed in, so you can join their pre-login activity to their account. A linked
`identify`, which is the default, captures the current anonymous id only when
none is stored, so later identifies do not overwrite it. `signOut`, and an
`identify` with `linkAnonymous: false`, clear it. Read it after awaiting the
call that should have changed it.

## Configuration

Pass a `CoproductConfig` to `initialize`. Every field has a default, and an
invalid value throws `InvalidConfig` rather than being silently corrected:

| Field | Default | Notes |
|---|---|---|
| `pollInterval` | 60 seconds | How often the SDK checks for updated flags. Must be at least 30 seconds |
| `startupTimeout` | 5 seconds | How long `initialize` waits for startup to settle. Must be positive |
| `requestTimeout` | 30 seconds | Bounds a single request for flags |
| `endpoint` | Coproduct's endpoint | `http` or `https`, with a host, and no query or fragment |
| `pollOnForeground` | `true` | Check for updates when the app returns to the foreground |

`startupTimeout` is a ceiling on waiting, not a promise about timing.
`initialize` returns as soon as startup settles, which is usually sooner, and
when the budget expires it stops waiting and returns anyway. Some required setup
runs outside the budget, so the call can also take slightly longer than the value
you set. Flags keep downloading in the background either way.

Calling `initialize` again with the same key and config gives you the same
client. A different key or config throws `CoproductAlreadyInitialized`.

## Seeing a flag change while you develop

Change a flag in Coproduct and your app will not notice immediately. The SDK
checks for updates every `pollInterval`, which defaults to sixty seconds, so a
change can take that long to appear.

Two ways to see it sooner:

- **Background the app and bring it back.** With `pollOnForeground` left at its
  default of `true`, returning to the foreground triggers an immediate check.
  This is the fastest loop and needs no code change. It does not apply while the
  SDK is backing off after failed checks, or once it has stopped for a rejected
  key, both of which `client.state` reports.
- **Lower `pollInterval` while developing.** Thirty seconds is the floor, so this
  halves the wait at most. Backgrounding is usually quicker.

If a change still does not appear after a refresh, the flag is not reaching your
app at all rather than arriving late. See
[Troubleshooting](#troubleshooting).

## SDK status

`client.state` tells you what the SDK is doing. **Most apps never need it**,
because getters and observations serve your defaults whenever real values are
unavailable. Read it for diagnostics, a debug screen, or logging:

| State | Meaning |
|---|---|
| `notReady` | No flags downloaded yet |
| `ready` | Flags are downloaded and serving |
| `retrying` | A download failed and is being retried |
| `stale` | Downloads have failed repeatedly. The last flags received are still served |
| `fatal` | Stopped. The SDK key was rejected or the endpoint refused permanently |

`state` is a plain getter with no listener, so read it when you need it rather
than watching it. If what you actually want is to react when flags arrive, do not
wait on `state` at all: observe the flag you care about, with
`CoproductFlagBuilder` or `observeBool`, and it rebuilds on its own once real
values land. `fatal` is worth logging: it means downloads have stopped and
will not resume, and a rejected key also clears the saved flags, so reads fall
back to your defaults.

`Coproduct.shutdown()` stops everything and closes the connection. Afterward
getters serve their defaults and existing observations keep their last value and
stop updating. It is safe to call more than once, and a later `initialize`
starts fresh.

A later `initialize` returns a **new** client. If you keep the client in a
Provider, a Riverpod container, or a BLoC, replace it there too: the old
instance stays callable and silently serves defaults forever. Most apps only
need `shutdown` at final teardown, so this rarely comes up.

Use the client on the isolate that created it. It holds a handle to the native
evaluation core, so do not pass a `CoproductClient` or a `FlagObservation`
through a `SendPort` to a worker isolate. Read flags on the main isolate and
send the resulting values instead.

## Troubleshooting

**A flag always returns the default I passed.** Work through these in order:

1. The flag key is misspelled, or no flag with that key exists for the SDK key
   you are using. This is by far the most common cause.
2. The flags have not arrived yet. Check `client.state`; `notReady` means
   nothing has downloaded.
3. The flag's type does not match the getter. A string flag read with `getBool`
   returns your default.
4. The flag targets an identity you have not set. Call `identify` and confirm
   your attribute names match the rules configured on the flag.

**My widget does not update when I change the flag.** Two different causes. If
the value never updates no matter how long you wait, you are probably calling a
getter inside `build`; use `CoproductFlagBuilder` or an observation instead, and
see [Which read API should I use?](#which-read-api-should-i-use). If it updates
eventually but not straight away, that is the poll interval, and
[Seeing a flag change while you develop](#seeing-a-flag-change-while-you-develop)
shows how to shorten the wait.

**`initialize` throws `CoproductAlreadyInitialized`.** Something already
initialized the SDK with a different key or config. Initialize once, at startup.

**`identify` throws `InvalidTargetingKey`.** The identifier was empty. Pass your
account's stable id.

## Testing your widgets

`package:coproduct/testing.dart` gives you a real client backed by values you set
in the test, with no SDK key, no network, and nothing to mock:

```dart
final harness = CoproductTestHarness()..setBool('new-checkout', false);
addTearDown(harness.shutdown);

await tester.pumpWidget(MaterialApp(
  home: CoproductScope(client: harness.client, child: const CheckoutPage()),
));

harness.setBool('new-checkout', true);
await tester.pumpAndSettle();
```

The harness supplies resolved values rather than evaluating targeting rules: set
the result your scenario needs. See [doc/testing.md](doc/testing.md).

## A complete example

[`example/lib/main.dart`](example/lib/main.dart) is a complete, working
integration to read. It installs a `CoproductScope`, reads a flag through
`CoproductFlagBuilder` with no `client` argument, and puts a getter read beside
it so you can watch the difference: the observation follows changes, the getter
does not.

It starts up differently from the Quickstart above, rendering its shell first
and initializing afterward, which keeps the first frame immediate. Both shapes
are fine.

The copy published on pub.dev is source to read under the Example tab. To run
it, paste `example/lib/main.dart` into a new app that depends on `coproduct`
from pub.dev. That uses the prebuilt binaries, so it needs no Rust toolchain,
and it reads the key from the environment:

```sh
flutter run --dart-define=COPRODUCT_SDK_KEY=your_mobile_sdk_key
```

Building the example from a clone of this repository is a different thing: it
source-links the SDK and compiles the Rust core from source, so it additionally
needs Rust, Xcode, and the Android NDK. That is a maintainer workflow, described
in [DEVELOPMENT.md](https://github.com/coproducthq/coproduct-client-sdks/blob/main/DEVELOPMENT.md).

## Building from source

See [DEVELOPMENT.md](https://github.com/coproducthq/coproduct-client-sdks/blob/main/DEVELOPMENT.md) in the repository for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](LICENSE).
