# coproduct

Flutter SDK for [Coproduct](https://coproduct.app), a feature flag and
experimentation platform.

A **feature flag** is a value you control from Coproduct rather than from your
app's code: a switch that turns a feature on or off, or a piece of
configuration you can change without shipping a release.

Flags do not have to be the same for everybody. In Coproduct you attach
targeting rules to a flag, and those rules match on **attributes** your app
sends about the person using it, such as their plan, their region, or whether
they joined this month. That is how one flag serves `true` to the segment you
choose and `false` to everyone else, or serves a different limit to trial
accounts than to paid ones.

This SDK downloads your flags, works out which value applies to the current
person, and hands it to your widgets.

## Compatibility

| | Supported |
|---|---|
| Flutter | >= 3.38.1 |
| Dart | >= 3.10.0 |
| iOS deployment target | 15.0+ |
| Android minSdk | 24 |
| Gradle (Android side) | 9.x |

## Before you start

You need two things from Coproduct before any of the code below returns a real
value:

- **A mobile SDK key.** It looks like `cpk_mob_` followed by thirty-two
  characters, and it tells the SDK which flags to download.
- **A flag.** A **flag key** is the stable string your code uses to ask for one
  flag, like `new-checkout`. The examples below use a boolean flag with that
  key, so create one to follow along, or substitute a key you already have.

You create both in Coproduct, whose primary interface is the Coproduct MCP app,
so you can issue a mobile SDK key and create a flag from there.

If a flag key is wrong, missing, or of a different type than you asked for, the
SDK returns the default value you passed. It does not throw and it does not warn
you, so check your spelling first when a flag seems stuck.

## Installation

> The SDK is not yet published to pub.dev. Until it is, clone this repository
> and point a path dependency at the `sdks/flutter/coproduct` directory inside
> your checkout:

```yaml
dependencies:
  coproduct:
    path: /absolute/or/relative/path/to/coproduct-client-sdks/sdks/flutter/coproduct
```

After release, this becomes an ordinary version dependency.

## Quickstart

Start the SDK once, before your app runs, and put the client where your widgets
can find it. This is a complete `main`:

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

## Reading flags

Five getters, one per flag type. Each takes the flag key and the value to serve
when the flag cannot be resolved. Reach the client from a widget with
`CoproductScope.of(context)`, or keep the one `initialize` returned:

```dart
final client = CoproductScope.of(context);

client.getBool('new-checkout', false);
client.getString('greeting', 'Hello');
client.getInt('max-items', 10);
client.getNumber('rollout-ratio', 0.0);
client.getJson('checkout-config', const {'maxItems': 10});
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
final greeting = client.observeString('greeting', 'Hello');

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
downloaded, so values update immediately.

**Identity is not saved between launches.** Call `identify` again after
`initialize` every time your app starts, or your flags evaluate anonymously.

The other calls:

```dart
await client.updateAttributes({'seats': AttributeValue.number(5)});
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

`startupTimeout` is a budget, not a guarantee of promptness in both directions:
`initialize` returns as soon as startup settles, and at expiry it stops waiting
and returns anyway. Some required setup runs outside the budget, so the call can
take slightly longer than the value you set. Flags keep downloading in the
background either way.

Calling `initialize` again with the same key and config gives you the same
client. A different key or config throws `CoproductAlreadyInitialized`.

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
| `reconciling` | Never returned by `state`, and listed only because it exists in the type |

`state` is a plain getter with no listener, so read it when you need it rather
than watching it. `fatal` is worth logging: it means downloads have stopped and
will not resume, and a rejected key also clears the saved flags, so reads fall
back to your defaults.

`Coproduct.shutdown()` stops everything and closes the connection. Afterward
getters serve their defaults and existing observations keep their last value and
stop updating. It is safe to call more than once, and a later `initialize`
starts fresh.

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

**My widget does not update when I change the flag.** You are probably calling
a getter inside `build`. Use `CoproductFlagBuilder` or an observation instead;
see [Which read API should I use?](#which-read-api-should-i-use).

**`initialize` throws `CoproductAlreadyInitialized`.** Something already
initialized the SDK with a different key or config. Initialize once, at startup.

**`identify` throws `InvalidTargetingKey`.** The identifier was empty. Pass your
account's stable id.

## A runnable sample

[`example/`](example/) is a small app you can run. It installs a
`CoproductScope`, reads a flag through `CoproductFlagBuilder` with no `client`
argument, and puts a getter read beside it so you can watch the difference: the
observation follows changes, the getter does not.

It starts up differently from the Quickstart above, rendering its shell first
and initializing afterward, which keeps the first frame immediate. Both shapes
are fine; the example's README explains the trade.

## Building from source

See the repo-root [DEVELOPMENT.md](../../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../../LICENSE).
