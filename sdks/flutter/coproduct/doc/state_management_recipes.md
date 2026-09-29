# State management recipes

`FlagObservation<T>` is a plain `ValueListenable<T>` with a `dispose()`, so it
works with whatever your app already uses. This SDK depends on no state
management package, and none of the recipes below add one.

Every recipe that owns an observation answers the same two questions: **who
rebuilds** when a flag changes, and **who calls `dispose()`**.

## The value you get

An observation has a value immediately, so there is no loading state to handle
and nothing to guard against. Until the SDK has flags, from the network or from
the copy saved on an earlier launch, that value is the default you supplied,
and it updates when flags arrive.

It starts out equal to what the matching getter returns. After a change, the
getter can return the new value a moment before the observation notifies, and
then the two agree again.

`observeBool`, `observeString`, `observeInt`, and `observeNumber` give you a
non-nullable value. `observeJson` gives you `Object?`, and its `null` is a real
value: a flag serving the JSON document `null` resolves to Dart `null`, which is
different from the flag being unavailable. An unavailable flag resolves to the
default you supplied, whatever its type.

An observation notifies only when the value actually changes, so a refresh that
returns the same value does not rebuild anything.

## Recipe 1: let the builder own it

The simplest correct code. `CoproductFlagBuilder` creates the observation, keeps
it for the widget's lifetime, and disposes it on unmount. You never dispose
anything.

```dart
CoproductFlagBuilder.boolFlag(
  flagKey: 'new-checkout',
  defaultValue: false,
  builder: (context, enabled, child) =>
      enabled ? const NewCheckout() : const OldCheckout(),
)
```

Return this from `build`, or put it anywhere a widget is accepted.

It finds the client in the `CoproductScope` above it. If your app keeps the
client in Provider, Riverpod, or BLoC instead, pass it explicitly with
`client:` and you need no scope.

The observation is replaced only if the client, the flag key, or the default
changes, so a rebuilding ancestor does not repeatedly dispose and recreate its
SDK listener.

## Recipe 2: own it in a State

Use this when several widgets in one subtree read the same flag, or when you
need the value outside `build`.

```dart
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, required this.client});

  final CoproductClient client;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late final FlagObservation<bool> _newCheckout;

  @override
  void initState() {
    super.initState();
    _newCheckout = widget.client.observeBool('new-checkout', defaultValue: false);
  }

  @override
  void dispose() {
    _newCheckout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: _newCheckout,
        builder: (context, enabled, child) => Text('$enabled'),
      );
}
```

**You own disposal here.** Forgetting `dispose()` leaves an SDK listener
registered for as long as your app runs. `dispose()` is what releases it.

This registers against the client once, in `initState`. That is correct while
the client is stable for the State's lifetime, which is the normal case since
the SDK is initialized once at startup. If a widget can genuinely be given a
different client, replace the observation in `didUpdateWidget` when
`widget.client` changes, disposing the old one first, which is what
`CoproductFlagBuilder` already does for you.

## Recipe 3: reaching the client from deep in the tree

The client comes back from `Coproduct.initialize` at startup, and the widgets
that read flags are usually far below that. `CoproductScope` carries it down.

Install it once, above anything that reads a flag:

```dart
import 'package:coproduct/coproduct.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  // initialize reads the app version and cache directory through platform
  // plugins, so the binding has to exist before it runs
  WidgetsFlutterBinding.ensureInitialized();

  final client = await Coproduct.initialize(sdkKey: 'cpk_mob_...');
  runApp(CoproductScope(client: client, child: const MyApp()));
}
```

Then any descendant can omit `client` entirely:

```dart
CoproductFlagBuilder.stringFlag(
  flagKey: 'greeting',
  defaultValue: 'Hello',
  builder: (context, greeting, child) => Text(greeting),
)
```

And anything that needs the client itself reads it from the context, inside a
widget method or callback that has one:

```dart
onPressed: () async {
  await CoproductScope.of(context).identify(userId: account.id);
},
```

`CoproductScope.of` throws with a message naming both remedies when no scope is
above it, so a missing scope is a loud failure rather than a silent default.

This recipe is about reaching the client, not owning an observation. The
builder above still rebuilds itself and disposes its own observation.

Two things this scope deliberately does **not** do. It does not own SDK
lifetime: `Coproduct.shutdown()` is process-wide and is called by whatever set
the SDK up, not by a widget going away. And it does not create the client, so
your app decides what to show while `initialize` is still running.

## Recipe 4: Provider

If your app already keeps the client in a Provider, read it from there and pass
it explicitly. You do not need a `CoproductScope` as well. To expose the client
through Provider in the first place:

```dart
final client = await Coproduct.initialize(sdkKey: 'cpk_mob_...');
runApp(Provider<CoproductClient>.value(value: client, child: const MyApp()));
```

`ListenableProvider` calls the `dispose` callback you give it, which is exactly
what an observation needs. Place this inside `build`, below the Provider that
exposes your `CoproductClient`:

```dart
ListenableProvider<FlagObservation<bool>>(
  create: (context) =>
      context.read<CoproductClient>().observeBool('new-checkout', defaultValue: false),
  dispose: (_, observation) => observation.dispose(),
  child: Consumer<FlagObservation<bool>>(
    builder: (context, observation, child) =>
        observation.value ? const NewCheckout() : const OldCheckout(),
  ),
)
```

`Consumer` rebuilds when the observation notifies, and `ListenableProvider`
disposes it when the provider goes away.

Create the observation inside `create`. A `.value` provider does not own
disposal, so passing an already-built observation to one leaks it unless
something else disposes it.

## Recipe 5: Riverpod

Read the client from your own provider and pass it explicitly rather than
installing a `CoproductScope`. `clientProvider` below is yours, holding the
client `Coproduct.initialize` returned.

`autoDispose` releases the observation when nothing is watching it any more,
which is what you want for a screen:

```dart
final newCheckoutProvider =
    Provider.autoDispose<FlagObservation<bool>>((ref) {
  final observation =
      ref.watch(clientProvider).observeBool('new-checkout', defaultValue: false);
  ref.onDispose(observation.dispose);
  return observation;
});
```

Drop `autoDispose` only when you deliberately want one observation shared for
as long as the provider container lives.

That answers who disposes, but not who rebuilds: the provider yields the
observation object, and watching it does not rebuild when the observation
notifies, because the object itself never changes. Read the value through the
listenable:

```dart
Consumer(
  builder: (context, ref, child) => ValueListenableBuilder<bool>(
    valueListenable: ref.watch(newCheckoutProvider),
    builder: (context, enabled, child) =>
        enabled ? const NewCheckout() : const OldCheckout(),
  ),
)
```

If your Riverpod version ships a listenable-aware provider, using it instead is
equivalent. The rule that matters either way is that something must listen to
the observation for a rebuild to happen.

## Recipe 6: BLoC

If a repository provider already carries the client, pass it from there and skip
the `CoproductScope`. To expose it, wrap your app in
`RepositoryProvider<CoproductClient>.value(value: client, child: ...)`.

The Cubit forwards the observation's changes into its state and disposes the
observation in `close()`. A `Cubit` shows the ownership without event-handler
boilerplate:

```dart
class CheckoutCubit extends Cubit<bool> {
  // Created once by the factory and handed to the private constructor, so the
  // initial state can read the current value without observing twice
  factory CheckoutCubit(CoproductClient client) =>
      CheckoutCubit._(client.observeBool('new-checkout', defaultValue: false));

  CheckoutCubit._(FlagObservation<bool> observation)
      : _newCheckout = observation,
        // The observation already has its value, so the initial state is the
        // real one rather than a placeholder
        super(observation.value) {
    _newCheckout.addListener(_emitFlag);
  }

  final FlagObservation<bool> _newCheckout;

  void _emitFlag() => emit(_newCheckout.value);

  @override
  Future<void> close() {
    _newCheckout
      ..removeListener(_emitFlag)
      ..dispose();
    return super.close();
  }
}
```

Then wire it into the tree. Place this inside `build`, below the provider that
exposes your `CoproductClient`:

```dart
BlocProvider(
  create: (context) => CheckoutCubit(context.read<CoproductClient>()),
  child: BlocBuilder<CheckoutCubit, bool>(
    builder: (context, enabled) =>
        enabled ? const NewCheckout() : const OldCheckout(),
  ),
)
```

`BlocBuilder` rebuilds when the Cubit emits, `BlocProvider` closes the Cubit it
created, and `close()` removes the listener and disposes the observation.

With a full `Bloc`, the same shape applies with one addition: the listener calls
`add(...)`, so register a matching `on<CheckoutFlagChanged>` handler in the
constructor, or the first flag change throws because no handler is registered.

## Shutdown

After `Coproduct.shutdown()` an existing observation keeps its last value and
stops updating; it does not reset to the default. Disposing it afterward is
safe. An observation created after shutdown serves the default you supply.

## A note on these samples

The Provider, Riverpod, and BLoC samples use packages this SDK does not depend
on. Adjust names for the versions you use.
