# coproduct

Flutter SDK for [Coproduct](https://coproduct.app), a feature management and
experimentation platform.

This release covers feature flags: reading them, targeting them at users,
updating your UI when they change, and testing widgets that use them. It does
not include experiment tracking or record which variation a user saw.

A **feature flag** is a value you control from Coproduct rather than from your
app's code: a switch that turns a feature on or off, or a piece of
configuration you can change without shipping a release. In Coproduct you
attach targeting rules to a flag. The rules match on **attributes** that
describe the person using your app, so one flag can serve `true` to the users
you choose and `false` to everyone else.

## Contents

- [Quick start](#quick-start)
- [Requirements and platform support](#requirements-and-platform-support)
- [Key concepts](#key-concepts)
- [Initializing and shutting down](#initializing-and-shutting-down)
- [Reading flags](#reading-flags)
- [Reacting to flag changes](#reacting-to-flag-changes)
- [Identity and attributes](#identity-and-attributes)
- [Automatic attributes](#automatic-attributes)
- [Configuration](#configuration)
- [Checking for updates](#checking-for-updates)
- [SDK status](#sdk-status)
- [Errors](#errors)
- [Privacy and data](#privacy-and-data)
- [Testing your widgets](#testing-your-widgets)
- [Troubleshooting](#troubleshooting)
- [Example app](#example-app)
- [Building from source](#building-from-source)
- [License](#license)

## Quick start

Follow these steps in order. At the end, a widget in your app shows one of two
screens depending on a flag you control from Coproduct.

**1. Check the requirements.** You need Flutter 3.38.1 or later, and your app
must target iOS 15.0 or later and Android API 24 or later. See
[Requirements and platform support](#requirements-and-platform-support) for
the details and for raising those minimums in an existing app.

**2. Get an SDK key and create a flag.** At
[coproduct.app](https://coproduct.app):

1. Sign in and open the project you want the app to read flags from, or create
   one.
2. Issue a **mobile** SDK key for that project. It looks like `cpk_mob_`
   followed by 32 characters. This SDK accepts only mobile keys.
3. Create a boolean flag with the key `new-checkout`. The steps below use that
   key. You can substitute a boolean flag you already have.

If your team uses Coproduct from an AI assistant through the Coproduct MCP
app, you can ask it to issue the key and create the flag instead.

**3. Install the package.** From your app's directory:

```sh
flutter pub add coproduct
```

This adds the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  coproduct: ^1.0.0
```

The package ships prebuilt native libraries, so you do not need a Rust
toolchain.

**On iOS**, a new app's first build stops with an error saying the plugin
requires a higher minimum iOS deployment version. Set
`platform :ios, '15.0'` in `ios/Podfile` and the iOS Deployment Target to 15.0
in Xcode, then build again. See [iOS setup](#ios-setup).

**4. Initialize the SDK in `main`.** Start the SDK once, before your app runs,
and put the client where your widgets can find it. Replace `cpk_mob_...` with
your key.

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

On the first launch, `initialize` waits for your flags to download, for up to
five seconds, and then returns whether or not they arrived. On later launches
it starts from the flags saved on the last launch and returns without waiting
for the network. See
[Initializing and shutting down](#initializing-and-shutting-down).

The placeholder key `cpk_mob_...` makes `initialize` throw `MalformedSdkKey`,
so a key you forgot to replace fails straight away.

**5. Gate a widget on the flag.** `CoproductFlagBuilder` reads the flag,
rebuilds when it changes, and cleans up after itself. Use it anywhere below
the `CoproductScope`:

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

Show it from `MyApp`, for example as `MaterialApp(home: const CheckoutPage())`.
`NewCheckout` and `OldCheckout` stand in for two widgets from your app. Until
the SDK has flags, `enabled` is the `defaultValue` you passed, so the widget
always has something to render.

**6. Identify signed-in users.** Rules that target particular users need to
know who is using the app. Once your app knows who is signed in, call
`identify` with that user's stable id and any attributes your rules match on:

```dart
await client.identify(
  userId: account.id,
  attributes: {'plan': const AttributeValue.string('pro')},
);
```

The SDK does not save this between launches, so call it again on every launch
once you know who is signed in. See
[Identity and attributes](#identity-and-attributes).

That is a working integration. Flag changes you make in Coproduct reach the
running app on the next check for updates, which happens every 60 seconds and
whenever the app returns to the foreground. See
[Checking for updates](#checking-for-updates).

## Requirements and platform support

| | Supported |
|---|---|
| Flutter | 3.38.1 or later |
| Dart | 3.10.0 or later |
| Platforms | Android and iOS only |
| iOS deployment target | 15.0 or later |
| Android minSdk | 24 or later |
| Android Gradle Plugin | 8.11.1 or later |
| Gradle | 8.14 or later |

The Android versions are the ones `flutter create` generates on Flutter
3.38.1, and a new app on that release builds with the SDK without changing
them. Older versions are not tested. Web, macOS, Windows, and Linux are not
supported.

**Prebuilt native libraries.** You do not need a Rust toolchain to build an
app that depends on the SDK.

- On Android the package ships libraries for `arm64-v8a`, `armeabi-v7a`, and
  `x86_64`. Use an `arm64` or `x86_64` emulator image. 32-bit `x86` images are
  not supported.
- On iOS the simulator library is universal, covering Apple silicon and Intel
  Macs. The SDK constrains no architectures in your project.

### iOS setup

A new Flutter app has no `ios/Podfile` until its first iOS build generates
one. That build then stops with this error:

```text
Error: The plugin "coproduct" requires a higher minimum iOS deployment version than your application is targeting.
```

To fix it:

1. In the generated `ios/Podfile`, uncomment the `platform` line and set it to
   `platform :ios, '15.0'`.
2. In Xcode, set the iOS Deployment Target to 15.0. The build does not enforce
   this one, but without it the app installs on iOS versions the SDK cannot
   run on.
3. Build again.

The iOS plugin is distributed through CocoaPods. If your app has Flutter's
Swift Package Manager support turned on, Flutter prints a warning that this
plugin does not support Swift Package Manager and uses CocoaPods for it. The
warning is expected.

### Android setup

A new app on Flutter 3.38.1 or later already uses `minSdk = 24`. An app
created with an older Flutter may use a lower value. Check `minSdk` in
`android/app/build.gradle.kts` (or `android/app/build.gradle`) and raise it to
24 if needed.

## Key concepts

### Flags, flag keys, and default values

A **flag key** is the stable string your code uses to ask for one flag, such
as `new-checkout`. Every read passes a key and a **default value** (the
`defaultValue` argument): the value your code uses when the SDK cannot resolve
the flag. In prose this README also calls it your default.

Flags have four types: boolean, string, number, and JSON. Read each with the
matching getter, builder, or observation.

### What a read serves

| Situation | What you get |
|---|---|
| The flag is on and the user matches a targeting rule | That rule's value |
| The flag is on and the user matches no rule | The flag's fallthrough value, the value you set in Coproduct for everyone else |
| The flag is switched off or paused | The flag's off value, set in Coproduct |
| The flag depends on another flag (a prerequisite) that is not met, or its rules use a condition this SDK version does not understand | The flag's off value |
| The SDK has no flags yet: first launch, before the first download completes | Your default value |
| No flag with that key exists in your SDK key's environment | Your default value |
| The flag's type does not match the read, such as a string flag read with `getBool` | Your default value |
| The SDK key was rejected, or the SDK was shut down | Your default value |

A switched-off flag and a user who matches no rule both serve real values from
Coproduct, not your default. Your default appears only when the SDK cannot
resolve the flag at all.

Reads never throw. The trade-off is that a mistake is quiet: a misspelled key
or a flag of the wrong type serves your default with no error.

### Flags are evaluated on the device

The SDK downloads your flag definitions and their targeting rules, keeps them
up to date in the background, and works out on the device which value applies.
Reading a flag is an in-memory lookup. It makes no network request, so it
never blocks a build and never fails because the network is down.

The attributes you set with `identify` stay on the device. The SDK does not
send them to Coproduct. See [Privacy and data](#privacy-and-data).

## Initializing and shutting down

### What initialize does

`Coproduct.initialize` checks your SDK key and configuration, loads any flags
saved on an earlier launch, collects the
[automatic attributes](#automatic-attributes), and starts checking for
updates. Then it waits, and what it waits for depends on whether saved flags
exist:

| Launch | What `initialize` waits for | What reads serve when it returns |
|---|---|---|
| First launch, or no saved flags | The first download, for up to `startupTimeout` (5 seconds by default) | The downloaded flags, or your defaults if the download has not finished or failed |
| A later launch, with flags saved | Nothing from the network | The flags saved on the last launch. Fresh values replace them when the first check completes, a moment later |

On every launch `initialize` also waits, within the same `startupTimeout`, for
the automatic attributes. It never throws because of the network. A slow or
unreachable network delays startup by at most `startupTimeout`, and checks
continue in the background. See
[What startupTimeout bounds](#what-startuptimeout-bounds) for the exact limits.

If the first check on a first launch fails, for example because the device is
offline, `initialize` stops waiting straight away rather than waiting out
`startupTimeout`, and reads serve your defaults. On a later launch they serve
the saved flags. If Coproduct asks the SDK to slow down, `initialize` waits out
the timeout. Either way the SDK tries again after `pollInterval` or when the
app returns to the foreground.

The SDK saves the flags after each successful download, in your app's cache
directory, one copy per SDK key. A launch that finds a saved copy starts with
`client.state` set to `ready`. If the operating system clears your app's
cache, the next launch behaves like a first launch. A rejected SDK key deletes
the saved copy.

### Calling initialize again

Calling `initialize` again with the same key and config returns the same
client. A different key or config throws `CoproductAlreadyInitialized`. To
change either, call `Coproduct.shutdown()` first.

### Isolates and engines

Call `initialize` from your app's main isolate, not a spawned one. This is
about Dart isolates, not app lifecycle: an app running in the background is
fine. Each
`FlutterEngine` has its own main isolate and runs its own SDK instance, so
call `Coproduct.shutdown()` when a short-lived background engine is done. Use
a client on the isolate that created it: send flag values to a worker isolate,
not a `CoproductClient` or `FlagObservation`.

### Shutting down

`Coproduct.shutdown()` stops checking for updates and closes the SDK's network
connection. Afterward:

- getters on an existing client return your defaults;
- existing observations keep their last value and stop updating;
- identity calls on an existing client complete without effect.

It is safe to call more than once. A later `initialize` returns a **new**
client. If you keep the client in a Provider, a Riverpod container, or a BLoC,
replace it there too, because the old one keeps serving defaults. Most apps
call `shutdown` only at final teardown, if at all.

## Reading flags

### Which read API to use

| What you are doing | Use |
|---|---|
| Building UI that should change when the flag changes | **`CoproductFlagBuilder`**, the right choice for most flag-gated widgets. One entry point per type: `boolFlag`, `stringFlag`, `intFlag`, `numberFlag`, `jsonFlag` |
| Reading the current value once, in logic outside the widget tree | **The getters**: `getBool`, `getString`, `getInt`, `getNumber`, `getJson` |
| Holding a value in your own `State`, or in Provider, Riverpod, or BLoC | **The observations**: `observeBool`, `observeString`, `observeInt`, `observeNumber`, `observeJson` |

**Calling `getBool` inside `build` does not make your widget rebuild when the
flag changes.** It reads the value at that moment and nothing more. If the flag
changes while your screen is open, the screen keeps showing the old value until
something else rebuilds it. Use the builder for UI.

### Getters

There are five getters over four flag types. Each takes the flag key and your
default. Reach the client from a widget with `CoproductScope.of(context)`, or
keep the one `initialize` returned:

```dart
final client = CoproductScope.of(context);

client.getBool('new-checkout', defaultValue: false);
client.getString('greeting', defaultValue: 'Hello');
client.getInt('max-items', defaultValue: 10);
client.getNumber('rollout-ratio', defaultValue: 0.0);
client.getJson('checkout-config', defaultValue: const {'maxItems': 10});
```

Reads never throw, at any point in your app's life, including after
`shutdown`. See [What a read serves](#what-a-read-serves) for when your
default comes back.

### Type details

- **`getInt` reads a number flag.** There is no separate integer flag type, so
  create a number flag. `getInt` truncates a fractional value toward zero and
  serves your default for a value outside the signed 64-bit range.
- **`getJson` returns a native Dart value**: a map, list, string, number,
  bool, or null. The value is deeply unmodifiable, so copy it before changing
  it.
- **Pass `getJson` a JSON-encodable default**: null, a number, string, or
  bool, or lists and string-keyed maps of those. A default that cannot be
  encoded is returned exactly as you passed it.

## Reacting to flag changes

### CoproductFlagBuilder

`CoproductFlagBuilder` has one entry point per type, all shaped like the
boolean one in the [quick start](#quick-start): `boolFlag`, `stringFlag`,
`intFlag`, `numberFlag`, and `jsonFlag`.

- With no `client` argument, it finds the client in the `CoproductScope`
  above it. Pass `client:` to use a client from somewhere else.
- It takes an optional `child`, passed to `builder` unchanged. Put an
  expensive subtree that does not depend on the flag there, so it is not
  rebuilt when the flag changes.
- It disposes its own observation when it leaves the tree.

### Observations

To hold the value outside a builder, observe the flag:

```dart
final greeting = client.observeString('greeting', defaultValue: 'Hello');

greeting.value;                  // the current value, available immediately
greeting.addListener(_onChange); // called whenever it changes
greeting.dispose();              // required when you are done
```

A `FlagObservation<T>` is a `ValueListenable<T>`, so it works with
`ValueListenableBuilder` and with the state-management packages you already
use. It notifies only when the value actually changes.

**You must call `dispose()` when you are done.** `CoproductFlagBuilder` does
this for you, which is why it is the easier path.

### Provider, Riverpod, and BLoC

The SDK adds no state-management dependency, and a `FlagObservation` works
with all three. If your app already holds the client in one of them, pass it
as `client:` and skip `CoproductScope`. Whoever creates an observation
disposes it. Worked examples, plus one that uses no package, are in
[doc/state_management_recipes.md](doc/state_management_recipes.md).

## Identity and attributes

### The anonymous identity

Before you call `identify`, the SDK evaluates flags for an anonymous id. It
generates this id the first time the SDK runs and keeps it in secure storage,
so an anonymous user normally stays in the same rollout group across launches.
If secure storage cannot be read at launch, the SDK uses a temporary id for
that launch.

### identify

```dart
await client.identify(
  userId: account.id,                                    // your stable account id
  attributes: {'plan': const AttributeValue.string('pro')},
);
```

**Attributes are what your targeting rules match against.** A rule in
Coproduct such as "plan is pro" matches the attribute you send here, so the
names and values must match the rules on your flags exactly, including case.

Call `identify` as soon as you know who is signed in. **Identity is not saved
between launches.** For a session your app restores at launch, call `identify`
right after `initialize` and before `runApp`, so the first frame is evaluated
for that user rather than anonymously.

None of the identity calls makes a network request. Each one re-evaluates the
flags the SDK already has, so values update as soon as the call completes.

Await these calls. If you ignore the returned future and the call fails, the
error becomes an unhandled asynchronous error.

### The other identity calls

```dart
await client.updateAttributes({'seats': const AttributeValue.number(5)});
await client.removeAttributes(['seats']);
await client.setContext(targetingKey: team.id);
await client.signOut();
```

| Call | Effect |
|---|---|
| `identify(userId:, attributes:)` | Sets the user id and **replaces** your attributes. An attribute missing from the map is cleared |
| `updateAttributes(map)` | **Merges** into your attributes. Keys you leave out stay as they are |
| `removeAttributes(keys)` | Removes the named attributes |
| `setContext(targetingKey:, attributes:)` | Like `identify`, it replaces the identity and your attributes, but it takes the targeting key directly and does not touch `previousAnonymousId`. Use it when what you target is not a signed-in account, such as a team or a device |
| `signOut()` | Returns to this installation's anonymous id, clears your attributes, and clears `previousAnonymousId` |

`signOut` does not create a new anonymous id, so an anonymous rollout places
the device in the same group as before sign-in.

`identify` and `setContext` throw `InvalidTargetingKey` if the id is empty.

### Attribute values

An attribute value is one of five kinds:

```dart
const AttributeValue.string('pro')
const AttributeValue.number(5)     // stored as a double
const AttributeValue.bool(true)
AttributeValue.stringList(['beta', 'staff'])
const AttributeValue.nullValue()   // an explicit null, not a removed key
```

Pass large integer ids as strings. A number is stored as a double, so an
integer above 2^53 loses precision.

The SDK normalizes a few values for you: `country`, `continent`, and
`region_code` are uppercased, `locale` uses hyphens, and `os_version` and
`app_version` are padded to three parts.

### Reserved names

`user_id` and `targetingKey` are reserved. The SDK ignores them inside an
attribute map, so set identity through the `userId` or `targetingKey`
parameter. A rule on `user_id` always matches the id you passed to
`identify` or `setContext`, or the anonymous id before that.

### Your attributes and automatic ones

Your attributes and the [automatic attributes](#automatic-attributes) are
stored separately. If you set an attribute with the same name as an automatic
one, such as `locale`, your value is the one rules see while it is set. The
automatic value is kept, and it applies again when you remove yours with
`removeAttributes`. `identify`, `setContext`, and `signOut` never clear the
automatic attributes.

### Linking an anonymous session

`client.previousAnonymousId` returns the anonymous id captured when someone
signed in, so you can join their activity before sign-in to their account.

- `identify` captures the current anonymous id only when none is stored, so a
  later `identify` does not overwrite it.
- `identify` with `linkAnonymous: false`, and `signOut`, clear it.
- Read it after awaiting the call that should have changed it.

The SDK does not send it anywhere. Pass it to your own analytics or backend
alongside the signed-in id to link the two.

## Automatic attributes

The SDK sets ten attributes with no code from you, so you can target a
platform, an app version, a locale, tablets, users on cellular, or new users
straight away.

| Attribute | Value | Meaning | When it is set |
|---|---|---|---|
| `platform` | `"ios"` or `"android"` | The operating system | During `initialize` |
| `os_version` | String, three-part version, such as `"17.4.0"` | The OS version, padded to three parts: iOS `17.4` becomes `17.4.0`. A value that is not a plain dotted number, such as `2.0-beta`, is kept as is | During `initialize` |
| `app_version` | String, three-part version, such as `"2.3.0"` | Your app's version name, padded to three parts. A value that is not a plain dotted number, such as `2.0-beta`, is kept as is | During `initialize` |
| `app_build` | String, such as `"42"` | Your app's build number. A string, not a number | During `initialize` |
| `locale` | Language tag, such as `"en-US"` | The device's primary locale, not the locale your app selected | During `initialize` |
| `timezone` | IANA name, such as `"Europe/London"` | The device's time zone | During `initialize` |
| `device_type` | `"phone"` or `"tablet"`, or unset | The kind of device. Unset on a device that is neither | During `initialize` |
| `network_type` | `"wifi"`, `"cellular"`, `"ethernet"`, `"other"`, or `"none"` | How the device is connected right now | Live. No value until its first reading, which usually arrives during or shortly after initialization. `initialize` never waits for it |
| `first_seen_at` | Number, whole seconds since the Unix epoch, UTC | When the SDK first ran in this installation of your app | During `initialize`. Unset for a launch in which the device cannot give the SDK a trustworthy record |
| `session_count` | Number, starting at 1 | How many app launches have initialized the SDK, counting this one | Same as `first_seen_at` |

- **Most are read once, when `initialize` runs.** If the device's language or
  time zone changes while your app runs, the old value stays until the SDK is
  shut down and initialized again. `network_type` is the exception: it
  updates when the
  connection changes, and observations update with it.
- **One can arrive late.** Most values are ready when `initialize` returns. One
  whose source is slower than `startupTimeout` applies as soon as it arrives,
  and observations update. If a rule depends on one, prefer
  `CoproductFlagBuilder` or an observation over a single read taken straight
  after `initialize`.
- **Target numbers with numeric operators.** `first_seen_at` and
  `session_count` are numbers, so use `gte`, `lt`, and the other numeric
  operators.

See [doc/automatic_attributes.md](doc/automatic_attributes.md) for how
`device_type` is classified, how launches are counted, the details of
`network_type`, and when `first_seen_at` and `session_count` are left unset.

Coproduct also supplies approximate location attributes (`country`,
`continent`, `region_code`, `city`) derived from the request's IP address.
Your attributes and the automatic ones override them. See
[doc/automatic_attributes.md](doc/automatic_attributes.md#location-attributes-from-coproduct).

## Configuration

Pass a `CoproductConfig` to `initialize`:

```dart
final client = await Coproduct.initialize(
  sdkKey: 'cpk_mob_...',
  config: const CoproductConfig(
    pollInterval: Duration(seconds: 30),
    startupTimeout: Duration(seconds: 3),
  ),
);
```

Every field has a default. An invalid value throws `InvalidConfig` rather than
being silently corrected.

| Field | Default | Notes |
|---|---|---|
| `pollInterval` | 60 seconds | How often the SDK checks for updated flags. Must be at least 30 seconds |
| `startupTimeout` | 5 seconds | How long `initialize` waits for the first download and the automatic attributes. Must be positive |
| `requestTimeout` | 30 seconds | How long a single request for flags can take. Must be positive |
| `endpoint` | Coproduct's endpoint | `http` or `https`, with a host, and no query or fragment |
| `pollOnForeground` | `true` | Whether returning to the foreground triggers a check for updates |

### What startupTimeout bounds

`startupTimeout` limits how long `initialize` waits for two things: the first
download of your flags, and the automatic attributes. The limit starts when
you call `initialize`. `initialize` returns as soon as both are done, which on
a launch with saved flags is usually well under the limit. When the limit
passes, `initialize` stops waiting and returns. It never throws because of the
limit. It can return slightly after the limit, and work the limit cuts short
carries on in the background. See
[What startupTimeout does not bound](doc/automatic_attributes.md#what-startuptimeout-does-not-bound).

## Checking for updates

The SDK checks Coproduct for updated flags when it starts, then every
`pollInterval` (60 seconds by default). A change you make in Coproduct can take
that long to reach a running app.

### Seeing a change while you develop

- **Background the app and bring it back.** With `pollOnForeground` left at
  `true`, returning to the foreground triggers an immediate check. This is the
  quickest loop and needs no code change.
- **Lower `pollInterval` while developing.** Thirty seconds is the minimum, so
  this halves the wait at most. Backgrounding is usually quicker.

Returning to the foreground does not trigger a check while one is already
running, while the SDK is backing off (`stale`, or when Coproduct has asked it
to slow down), or after it has stopped (`fatal`).

If a change still does not appear after a refresh, the flag is not reaching
your app at all. See [Troubleshooting](#troubleshooting).

### When checks fail

- **A failed check** is retried at the normal `pollInterval`, and
  `client.state` becomes `retrying`. The SDK keeps serving the flags it has.
- **After five failed checks in a row**, `client.state` becomes `stale` and the
  SDK checks every five `pollInterval`s (five minutes by default) until one
  succeeds.
- **If Coproduct asks the SDK to slow down**, it waits as long as asked, up to
  an hour, and never less than `pollInterval`.
- **Regaining a network connection** does not by itself trigger a check. The
  next check happens at the next interval or when the app returns to the
  foreground.

## SDK status

`client.state` tells you what the SDK is doing. Its type is `ProviderState`.
**Most apps never need it**, because getters and observations serve your
defaults whenever real values are unavailable. Read it for diagnostics, a
debug screen, or logging:

| State | Meaning |
|---|---|
| `notReady` | The SDK has no flags yet: nothing is saved from an earlier launch, and no download has arrived. A failed check moves it to `retrying`, but a check that Coproduct asks to slow down leaves it here |
| `ready` | The SDK has flags, either downloaded in this session or loaded from the copy saved on an earlier launch |
| `retrying` | The last check failed, and the SDK is retrying at the normal interval. Any flags it already had are still served |
| `stale` | Five checks in a row have failed, and the SDK now checks less often. Any flags it already had are still served |
| `fatal` | Checks have stopped for this session. A rejected SDK key also deletes the saved flags, so reads serve your defaults. Any other rejection, such as an endpoint that answers `404`, keeps the flags the SDK had. An endpoint that cannot be reached leads to `retrying` and `stale` instead |

On a first launch with no saved flags, `retrying` and `stale` can also mean
the SDK has no flags at all.

`state` is a plain getter with no listener, so read it when you need it rather
than watching it. To react when flags arrive, observe the flag you care about
with `CoproductFlagBuilder` or an observation. A getter can return newly
downloaded values a moment before `state` reports `ready`.

`fatal` is worth logging: checks have stopped and will not resume until the
app restarts, or until you call `Coproduct.shutdown()` and then `initialize`
again.

## Errors

Flag reads never throw. `initialize` and the identity calls throw only for
mistakes in your code, never for network problems. Every exception the SDK
throws implements `CoproductException`. New subtypes may be added, so handle
unknown ones.

| Exception | Thrown by | When | What to do |
|---|---|---|---|
| `MissingSdkKey` | `initialize` | The SDK key is empty | Pass your mobile SDK key |
| `InvalidKeyType` | `initialize` | The key does not start with `cpk_mob_`, such as a server key. The exception carries no part of the key you passed | Issue a mobile key for your project |
| `MalformedSdkKey` | `initialize` | The key starts with `cpk_mob_` but has the wrong length or characters. `reason` says which | Copy the key again. It is `cpk_mob_` followed by 32 lowercase Crockford base32 characters: digits and letters other than `i`, `l`, `o`, and `u`, as issued by Coproduct |
| `InvalidConfig` | `initialize` | A `CoproductConfig` value is invalid. `field` names it and `reason` says why | Fix the value. See [Configuration](#configuration) |
| `CoproductAlreadyInitialized` | `initialize` | The SDK is already running with a different key or config | Initialize once, or call `Coproduct.shutdown()` first |
| `CoproductInitializationCancelled` | `initialize` | `Coproduct.shutdown()` ran before `initialize` finished | Expected if your app shuts down during startup. Catch it and stop |
| `CoproductUnsupportedIsolate` | `initialize` | Called from a spawned background isolate | Call it from your app's main isolate |
| `InvalidTargetingKey` | `identify`, `setContext` | The user id or targeting key is empty | Pass a non-empty stable id |
| `UnsupportedSchemaVersion` | None | Reserved. This version never throws it | Nothing |

**A key with the right format that Coproduct rejects does not throw.** For
example, a revoked key passes the format checks, so `initialize` succeeds.
The first check is then rejected, `client.state` becomes `fatal`, and reads
serve your defaults.

**These problems are reported instead of thrown**, because no call is waiting
on them. The SDK passes them to `FlutterError.onError`, with `library` set to
`coproduct`, once per `initialize`, in every build mode:

| Reported | Meaning |
|---|---|
| `HostContextUnavailable` | The SDK's native plugin did not answer on the host-context or network-type channel, so one or more of `device_type`, `network_type`, `first_seen_at`, and `session_count` may be absent or no longer updating |
| `SessionAttributesUnavailable` | The SDK could not read or save its launch record, so `first_seen_at` and `session_count` are unset for this launch. `cause` is `SessionAttributesUnavailableCause.storageFailure` (the device's storage failed, or could not be trusted, for example before the first unlock after a restart) or `SessionAttributesUnavailableCause.malformedResponse` (the native side returned something unreadable). More causes may be added, so a `switch` on it needs a default branch |

See [Troubleshooting](#troubleshooting) for what to do about each.

The SDK also reports unexpected internal errors through `FlutterError.onError`
with `library` set to `coproduct`. It keeps running after them.

`CoproductScope.of(context)` throws a `FlutterError` when no `CoproductScope`
is above `context`. The message names both fixes: add a scope, or pass the
client explicitly.

## Privacy and data

### What the SDK sends

Each check for updates is a request to Coproduct's endpoint, over HTTPS unless
you configure an `http` endpoint. It carries:

- your SDK key;
- a `User-Agent` of `coproduct-flutter/` followed by the SDK version;
- a tag identifying the flags the SDK already has, so an unchanged response
  can be skipped.

It carries no attributes, no user ids, and no anonymous id. Flags are
evaluated on the device.

Coproduct sees the IP address of each request, as any server does. It uses the
address to derive the approximate location attributes `country`, `continent`,
`region_code`, and `city`, and a time zone, and returns them with your flags.
See [doc/automatic_attributes.md](doc/automatic_attributes.md#location-attributes-from-coproduct).

### What the SDK stores on the device

| Data | Where | Why |
|---|---|---|
| A random anonymous id | The Keychain on iOS. Encrypted storage on Android | So an anonymous user keeps the same rollout group across launches. On iOS, Keychain items can survive an app uninstall, so the id can outlive a reinstall |
| The last downloaded flags, with the approximate location Coproduct derived for the device (`country`, `continent`, `region_code`, `city`, and a time zone) | Your app's cache directory, one copy per SDK key | So later launches start with flags. See [What initialize does](#what-initialize-does) |
| The launch record for `first_seen_at` and `session_count` | `UserDefaults` on iOS. A private `SharedPreferences` file on Android | To count launches |

The user id you pass to `identify` and the attributes you set are held in
memory only.

### Android permission

The SDK declares the `ACCESS_NETWORK_STATE` permission to read the connection
type for `network_type`. It is a normal permission: Android grants it at
install without a prompt. It merges into your app's manifest automatically.

### iOS privacy manifest

The SDK ships a `PrivacyInfo.xcprivacy` privacy manifest. It declares:

- no tracking and no tracking domains;
- no collected data types;
- access to `UserDefaults`, with reason `CA92.1`, for the launch record.

Xcode includes it in your app's privacy report. Google Play's Data safety form
and Apple's App Privacy details can treat the approximate location above as
collected data. Check both against Coproduct's data retention policy before
you submit your app.

## Testing your widgets

`package:coproduct/testing.dart` gives you a real client backed by values you
set in the test, with no SDK key, no network, and nothing to mock:

```dart
final harness = CoproductTestHarness()..setBool('new-checkout', false);
addTearDown(harness.shutdown);

await tester.pumpWidget(MaterialApp(
  home: CoproductScope(client: harness.client, child: const CheckoutPage()),
));

harness.setBool('new-checkout', true);
await tester.pumpAndSettle();
```

The harness supplies resolved values rather than evaluating targeting rules,
so set the result your scenario needs. See [doc/testing.md](doc/testing.md).

## Troubleshooting

**A flag always returns the default I passed.** Your default appears only
when the SDK cannot resolve the flag. Work through these in order:

1. The flag key is misspelled, or no flag with that key exists in the
   environment of your SDK key. This is the most common cause.
2. The flag's type does not match the read. A string flag read with `getBool`
   returns your default.
3. The SDK has no flags yet. `client.state` is `notReady` before the first
   check completes. On a first launch with no saved flags, `retrying` and
   `stale` mean the checks are failing and nothing has downloaded.
4. The SDK key was rejected. `client.state` is `fatal`, and the saved flags
   were deleted.
5. You are reading from a client left over from before `Coproduct.shutdown()`.
   Use the client the latest `initialize` returned.

**A flag returns a value, but not the one I expect for this user.**

- A switched-off or paused flag serves its off value, and a user who matches
  no rule gets the fallthrough value. Check the flag's state and rules in
  Coproduct.
- Confirm that you called `identify` on this launch, after `initialize`.
  Identity is not saved between launches.
- Check that your attribute names and values match the rule exactly,
  including case.
- An attribute you set overrides an automatic attribute with the same name.
  See [Your attributes and automatic ones](#your-attributes-and-automatic-ones).
- A flag whose prerequisite is not met serves its off value even when it is
  switched on. So does a flag whose rules use a condition this SDK version
  does not understand. Check its prerequisites, and update the SDK if the flag
  uses a newer operator.
- If you just changed the flag, the app may not have checked for updates yet.
  See [Checking for updates](#checking-for-updates).

**The app shows last session's value for a moment after launch.** This is the
saved copy from the previous launch. The SDK serves it straight away and
replaces it when the first check completes. See
[What initialize does](#what-initialize-does).

**My widget does not update when I change the flag.** If the value never
updates however long you wait, you are probably calling a getter inside
`build`. Use `CoproductFlagBuilder` or an observation instead. See
[Which read API to use](#which-read-api-to-use). If it updates eventually,
that is the interval between checks. See
[Seeing a change while you develop](#seeing-a-change-while-you-develop).

**`initialize` or `identify` throws.** See [Errors](#errors) for each
exception and what to do about it.

**`FlutterError.onError` reports `HostContextUnavailable`.** The SDK's native
plugin did not answer on the host-context or network-type channel. Either it
is not registered on the engine that ran `initialize`, or its native side is
older than the Dart side. One or more of `device_type`, `network_type`,
`first_seen_at`, and `session_count` may then be absent or no longer
updating. Rules that need an absent attribute to have a value do not match,
and an `is_not_set` rule on it does. Flags otherwise evaluate normally. To fix
it:

- If you add Flutter to an existing native app, make sure plugins are
  registered on every `FlutterEngine` you create.
- If you just upgraded the SDK, stop the app and rebuild it. A hot restart
  does not rebuild the native side.

**`FlutterError.onError` reports `SessionAttributesUnavailable`.**
`first_seen_at` and `session_count` are unset until the next launch. Check
`cause` (see [Errors](#errors)). A storage failure can mean a launch before
the device's first unlock, which needs no action. On Android the exception is
in logcat under the tag `Coproduct`.

**The debug console shows `coproduct: automatic attribute ... was not
available when initialize returned`.** Either the attribute's source was
slower than `startupTimeout`, in which case the value applies as soon as it
arrives and rules that use it start matching a moment later, or the device has
no value for it, such as `device_type` on a television or a Chromebook, in
which case it stays unset. These lines appear in debug builds only.

## Example app

[`example/lib/main.dart`](example/lib/main.dart) is a complete integration. It
installs a `CoproductScope`, reads a flag through `CoproductFlagBuilder`, and
shows a getter read beside it so you can see that the builder follows changes
and the getter does not. It renders its first frame before initializing,
the opposite of the quick start. Both approaches are supported. See
[example/README.md](example/README.md) for how to run it.

## Building from source

See [DEVELOPMENT.md](https://github.com/coproducthq/coproduct-client-sdks/blob/main/DEVELOPMENT.md)
in the repository for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](LICENSE).
