# State management recipes

`FlagObservation<T>` is a plain `ValueListenable<T>` with a `dispose()`, so it
works with whatever this app already uses. This SDK depends on no state
management package, and none of the recipes below add one.

Every recipe answers the same two questions: **who rebuilds** when a flag
changes, and **who calls `dispose()`**.

## The value you get

An observation is seeded synchronously with whatever the matching getter would
return at that moment, so there is no loading state to handle and no separate
"not ready yet" sentinel to guard. That makes it consistent with the getter, not
necessarily current with the server: an observation created before the first
poll lands serves the default you supplied, and updates when a snapshot arrives.

`observeBool`, `observeString`, `observeInt`, and `observeNumber` give you a
non-nullable value. `observeJson` gives you `Object?`, and its `null` is a real
value: a flag serving the JSON document `null` resolves to Dart `null`, which is
different from the flag being unavailable. An unavailable flag resolves to the
default you supplied, whatever its type.

An observation notifies only when the value actually changes, so a poll that
re-delivers the same value does not rebuild anything.

## Recipe 1: let the builder own it

The simplest correct code. `CoproductFlagBuilder` creates the observation, keeps
it for the widget's lifetime, and disposes it on unmount. You never dispose
anything.

```dart
CoproductFlagBuilder.boolFlag(
  client: client,
  flagKey: 'new-checkout',
  defaultValue: false,
  builder: (context, enabled, child) =>
      enabled ? const NewCheckout() : const OldCheckout(),
)
```

The observation is replaced only if the client, the flag key, or the default
changes, so a rebuilding ancestor does not churn native sessions.

## Recipe 2: own it in a State

Use this when several widgets in one subtree read the same flag, or when you
need the value outside `build`.

```dart
class _CheckoutPageState extends State<CheckoutPage> {
  late final FlagObservation<bool> _newCheckout;

  @override
  void initState() {
    super.initState();
    _newCheckout = widget.client.observeBool('new-checkout', false);
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

**You own disposal here.** An observation holds a native subscription, so
forgetting `dispose()` leaks it. Cancelling a stream subscription you obtained
elsewhere does not end the native session, and `dispose()` does.

This registers against the client once, in `initState`. That is correct while
the client is stable for the State's lifetime, which is the normal case since
the SDK is initialized once at startup. If a widget can genuinely be given a
different client, replace the observation in `didUpdateWidget` when
`widget.client` changes, disposing the old one first, which is what
`CoproductFlagBuilder` already does for you.

## Recipe 3: reaching the client from deep in the tree

The client comes back from `Coproduct.initialize` at startup, and the widgets
that read flags are usually far below that. An `InheritedWidget` carries it down
without any package:

```dart
class CoproductScope extends InheritedWidget {
  const CoproductScope({
    super.key,
    required this.client,
    required super.child,
  });

  final CoproductClient client;

  static CoproductClient of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CoproductScope>();
    assert(scope != null, 'No CoproductScope found above this widget');
    return scope!.client;
  }

  @override
  bool updateShouldNotify(CoproductScope oldWidget) =>
      !identical(client, oldWidget.client);
}
```

Install it once, above anything that reads a flag:

```dart
final client = await Coproduct.initialize(sdkKey: 'your-key');
runApp(CoproductScope(client: client, child: const MyApp()));
```

Then any descendant reads it from the context:

```dart
CoproductFlagBuilder.stringFlag(
  client: CoproductScope.of(context),
  flagKey: 'greeting',
  defaultValue: 'Hello',
  builder: (context, greeting, child) => Text(greeting),
)
```

Two things this scope deliberately does **not** do. It does not own SDK
lifetime: `Coproduct.shutdown()` is process-wide and is called by whatever set
the SDK up, not by a widget going away. And it does not create the client, so
your app decides what to show while `initialize` is still running.

## Recipe 4: Provider

`ListenableProvider` disposes what it creates, which is what an observation
needs:

```dart
ListenableProvider<FlagObservation<bool>>(
  create: (_) => client.observeBool('new-checkout', false),
  dispose: (_, observation) => observation.dispose(),
  child: Consumer<FlagObservation<bool>>(
    builder: (context, observation, child) =>
        observation.value ? const NewCheckout() : const OldCheckout(),
  ),
)
```

Create the observation inside `create`. A `.value` provider does not own
disposal, so passing an already-built observation to one leaks it unless
something else disposes it.

## Recipe 5: Riverpod

A provider owns the observation's lifetime, and `ref.onDispose` ties the native
session to it. A plain `Provider` lives as long as its container, so reach for
`Provider.autoDispose` when the observation should be released with the screen
that watched it. `clientProvider` below is your own provider holding the client
returned by `Coproduct.initialize`:

```dart
final newCheckoutProvider = Provider<FlagObservation<bool>>((ref) {
  final observation =
      ref.watch(clientProvider).observeBool('new-checkout', false);
  ref.onDispose(observation.dispose);
  return observation;
});
```

That answers who disposes, but not who rebuilds: a plain `Provider` yields the
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

Forward the observation's notifications into your state and dispose it in
`close()`. A `Cubit` shows the ownership without event-handler boilerplate:

```dart
class CheckoutCubit extends Cubit<bool> {
  // Registered once by the factory and handed to the private constructor, so
  // the initial state can read the seeded value without observing twice
  factory CheckoutCubit(CoproductClient client) =>
      CheckoutCubit._(client.observeBool('new-checkout', false));

  CheckoutCubit._(FlagObservation<bool> observation)
      : _newCheckout = observation,
        // The observation is already seeded, so the initial state is the real
        // value rather than a placeholder
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

With a full `Bloc`, the same shape applies with one addition: the listener calls
`add(...)`, so register a matching `on<CheckoutFlagChanged>` handler in the
constructor, or the first flag change throws for want of a handler.

## Shutdown

After `Coproduct.shutdown()` an existing observation keeps its last value and
stops updating; it does not reset to the default. Disposing it afterward is
safe. An observation created after shutdown serves the default you supply.

## A note on these samples

The `CoproductScope` recipe is compiled and checked by this package's own test
suite. The Provider, Riverpod, and BLoC samples reference packages this SDK does
not depend on, so they are reviewed by hand rather than compiled here. Adapt
names to your version of those packages.
