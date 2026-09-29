import 'package:flutter/widgets.dart';

// The public client type lives in the package entrypoint, which is the library
// this file's facade extends. Importing it by package URI keeps the facade next
// to the widget it wraps rather than splitting the two across libraries
// FlagObservation comes through that same entrypoint, which re-exports it
// Importing lib/src/flag_observation.dart as well is redundant and analyze
// reports it
import 'package:coproduct/coproduct.dart';

import 'json_value.dart';

/// Builds a widget from a flag's current value, and rebuilds it when the value
/// changes. The right choice for most flag-gated widgets.
///
/// Each entry point creates an observation of the flag when the widget is
/// first built, rebuilds the subtree when the value changes, and disposes the
/// observation when the widget is removed, so you never manage its lifetime.
/// Until the SDK has flags, the value is the default value you passed.
///
/// ```dart
/// CoproductFlagBuilder.boolFlag(
///   flagKey: 'new-checkout',
///   defaultValue: false,
///   builder: (context, enabled, child) =>
///       enabled ? const NewCheckout() : const OldCheckout(),
/// )
/// ```
///
/// Every entry point takes the same arguments:
///
/// - `client` is optional. Without it, the builder uses the client from the
///   nearest [CoproductScope] above it, and throws if there is none. Pass it
///   when something else holds the client, such as Provider, Riverpod, or
///   BLoC, and then no scope is needed.
/// - `flagKey` and `defaultValue` are the same as for the matching getter,
///   such as `CoproductClient.getBool`.
/// - `builder` receives the current value and `child`.
/// - `child` is optional and passed to `builder` unchanged. Put an expensive
///   subtree that does not depend on the flag there, so it is not rebuilt when
///   the flag changes.
///
/// The observation is replaced only when the client, the flag key, or the
/// default value changes, so a rebuilding parent does not repeatedly
/// re-register it. To share one observation across several widgets, hold a
/// [FlagObservation] yourself, pass it to `ValueListenableBuilder`, and dispose
/// it when you are done
final class CoproductFlagBuilder {
  // A namespace of typed entry points, never instantiated. The entry points are
  // static because a Dart constructor cannot specialize the generic widget's
  // type argument from the type of one of its arguments
  CoproductFlagBuilder._();

  /// Builds from a boolean flag, read as with `CoproductClient.getBool`
  static Widget boolFlag({
    Key? key,
    CoproductClient? client,
    required String flagKey,
    required bool defaultValue,
    required ValueWidgetBuilder<bool> builder,
    Widget? child,
  }) =>
      Builder(
        // The key belongs on the outer widget, because that is what
        // participates in sibling reconciliation at the call site. With it on
        // the inner widget, reordered siblings would match positionally and
        // the inner elements would be replaced rather than moved, which reads
        // correctly on screen while churning native sessions
        key: key,
        builder: (context) {
          // Short-circuits, so an explicit client never registers an inherited
          // dependency and a scope change cannot rebuild this subtree
          final resolved = client ?? CoproductScope.of(context);
          return ObservedFlagBuilder<bool>(
            clientIdentity: resolved,
            flagKey: flagKey,
            defaultValue: defaultValue,
            create: () => resolved.observeBool(flagKey, defaultValue: defaultValue),
            unchangedDefault: (a, b) => a == b,
            builder: builder,
            child: child,
          );
        },
      );

  /// Builds from a string flag, read as with `CoproductClient.getString`
  static Widget stringFlag({
    Key? key,
    CoproductClient? client,
    required String flagKey,
    required String defaultValue,
    required ValueWidgetBuilder<String> builder,
    Widget? child,
  }) =>
      Builder(
        key: key,
        builder: (context) {
          final resolved = client ?? CoproductScope.of(context);
          return ObservedFlagBuilder<String>(
            clientIdentity: resolved,
            flagKey: flagKey,
            defaultValue: defaultValue,
            create: () => resolved.observeString(flagKey, defaultValue: defaultValue),
            unchangedDefault: (a, b) => a == b,
            builder: builder,
            child: child,
          );
        },
      );

  /// Builds from a number flag read as an integer, as with
  /// `CoproductClient.getInt`. A fractional value is truncated toward zero
  static Widget intFlag({
    Key? key,
    CoproductClient? client,
    required String flagKey,
    required int defaultValue,
    required ValueWidgetBuilder<int> builder,
    Widget? child,
  }) =>
      Builder(
        key: key,
        builder: (context) {
          final resolved = client ?? CoproductScope.of(context);
          return ObservedFlagBuilder<int>(
            clientIdentity: resolved,
            flagKey: flagKey,
            defaultValue: defaultValue,
            create: () => resolved.observeInt(flagKey, defaultValue: defaultValue),
            unchangedDefault: (a, b) => a == b,
            builder: builder,
            child: child,
          );
        },
      );

  /// Builds from a number flag, read as with `CoproductClient.getNumber`
  static Widget numberFlag({
    Key? key,
    CoproductClient? client,
    required String flagKey,
    required double defaultValue,
    required ValueWidgetBuilder<double> builder,
    Widget? child,
  }) =>
      Builder(
        key: key,
        builder: (context) {
          final resolved = client ?? CoproductScope.of(context);
          return ObservedFlagBuilder<double>(
            clientIdentity: resolved,
            flagKey: flagKey,
            defaultValue: defaultValue,
            create: () => resolved.observeNumber(flagKey, defaultValue: defaultValue),
            unchangedDefault: (a, b) => a == b || (a.isNaN && b.isNaN),
            builder: builder,
            child: child,
          );
        },
      );

  /// Builds from a JSON flag, read as with `CoproductClient.getJson`. The value
  /// is a deeply unmodifiable Dart value: a map, list, string, number, bool, or
  /// null
  static Widget jsonFlag({
    Key? key,
    CoproductClient? client,
    required String flagKey,
    required Object? defaultValue,
    required ValueWidgetBuilder<Object?> builder,
    Widget? child,
  }) =>
      Builder(
        key: key,
        builder: (context) {
          final resolved = client ?? CoproductScope.of(context);
          return ObservedFlagBuilder<Object?>(
            clientIdentity: resolved,
            flagKey: flagKey,
            defaultValue: defaultValue,
            create: () => resolved.observeJson(flagKey, defaultValue: defaultValue),
            // Defaults are compared the way the observation resolves them, so
            // two objects that encode to the same document are one default
            unchangedDefault: jsonDefaultsEqual,
            builder: builder,
            child: child,
          );
        },
      );
}

/// The generic widget behind every [CoproductFlagBuilder] entry point.
///
/// Not exported from the package entrypoint: the public surface is the typed
/// facade. It takes a [create] callback rather than a client so its lifetime
/// rules are testable without a native library
class ObservedFlagBuilder<T> extends StatefulWidget {
  const ObservedFlagBuilder({
    super.key,
    required this.clientIdentity,
    required this.flagKey,
    required this.defaultValue,
    required this.create,
    required this.unchangedDefault,
    required this.builder,
    this.child,
  });

  /// Compared by identity to decide whether the observation must be replaced
  final Object clientIdentity;
  final String flagKey;
  final T defaultValue;
  final FlagObservation<T> Function() create;

  /// The same equality the observation applies to its own values, so a default
  /// the observation would call unchanged does not force a re-registration
  final bool Function(T a, T b) unchangedDefault;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  State<ObservedFlagBuilder<T>> createState() => _ObservedFlagBuilderState<T>();
}

class _ObservedFlagBuilderState<T> extends State<ObservedFlagBuilder<T>> {
  late FlagObservation<T> _observation;

  @override
  void initState() {
    super.initState();
    _observation = widget.create();
  }

  @override
  void didUpdateWidget(ObservedFlagBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The create callback is deliberately not compared. A parent that rebuilds
    // passes a fresh closure every time, so comparing it would re-register a
    // native session on every frame
    final same = identical(widget.clientIdentity, oldWidget.clientIdentity) &&
        widget.flagKey == oldWidget.flagKey &&
        widget.unchangedDefault(widget.defaultValue, oldWidget.defaultValue);
    if (same) return;
    _observation.dispose();
    _observation = widget.create();
  }

  @override
  void dispose() {
    _observation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
        valueListenable: _observation,
        builder: widget.builder,
        child: widget.child,
      );
}
