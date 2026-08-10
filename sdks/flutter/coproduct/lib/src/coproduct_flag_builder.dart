import 'package:flutter/widgets.dart';

// The public client type lives in the package entrypoint, which is the library
// this file's facade extends. Importing it by package URI keeps the facade next
// to the widget it wraps rather than splitting the two across libraries
// FlagObservation comes through that same entrypoint, which re-exports it
// Importing lib/src/flag_observation.dart as well is redundant and analyze
// reports it
import 'package:coproduct/coproduct.dart';

import 'json_value.dart';

/// Builds a widget from a flag's live value, owning the observation for you.
///
/// Each entry point creates its observation when the widget is first built,
/// rebuilds the subtree when the value changes, and disposes the observation
/// when the widget is removed, so a builder user never manages a lifetime.
///
/// ```dart
/// CoproductFlagBuilder.boolFlag(
///   client: client,
///   flagKey: 'new-checkout',
///   defaultValue: false,
///   builder: (context, enabled, child) =>
///       enabled ? const NewCheckout() : const OldCheckout(),
/// )
/// ```
///
/// The observation is replaced only when the client, the flag key, or the
/// default changes, so a rebuilding ancestor does not churn native sessions. An advanced caller who wants to share one observation across
/// several widgets can hold a [FlagObservation] directly, pass it to
/// `ValueListenableBuilder`, and dispose it themselves
class CoproductFlagBuilder {
  // A namespace of typed entry points, never instantiated. The entry points are
  // static because a Dart constructor cannot specialize the generic widget's
  // type argument from the type of one of its arguments
  CoproductFlagBuilder._();

  /// Builds from a boolean flag
  static Widget boolFlag({
    Key? key,
    required CoproductClient client,
    required String flagKey,
    required bool defaultValue,
    required ValueWidgetBuilder<bool> builder,
    Widget? child,
  }) =>
      ObservedFlagBuilder<bool>(
        key: key,
        clientIdentity: client,
        flagKey: flagKey,
        defaultValue: defaultValue,
        create: () => client.observeBool(flagKey, defaultValue),
        unchangedDefault: (a, b) => a == b,
        builder: builder,
        child: child,
      );

  /// Builds from a string flag
  static Widget stringFlag({
    Key? key,
    required CoproductClient client,
    required String flagKey,
    required String defaultValue,
    required ValueWidgetBuilder<String> builder,
    Widget? child,
  }) =>
      ObservedFlagBuilder<String>(
        key: key,
        clientIdentity: client,
        flagKey: flagKey,
        defaultValue: defaultValue,
        create: () => client.observeString(flagKey, defaultValue),
        unchangedDefault: (a, b) => a == b,
        builder: builder,
        child: child,
      );

  /// Builds from an integer flag
  static Widget intFlag({
    Key? key,
    required CoproductClient client,
    required String flagKey,
    required int defaultValue,
    required ValueWidgetBuilder<int> builder,
    Widget? child,
  }) =>
      ObservedFlagBuilder<int>(
        key: key,
        clientIdentity: client,
        flagKey: flagKey,
        defaultValue: defaultValue,
        create: () => client.observeInt(flagKey, defaultValue),
        unchangedDefault: (a, b) => a == b,
        builder: builder,
        child: child,
      );

  /// Builds from a numeric flag
  static Widget numberFlag({
    Key? key,
    required CoproductClient client,
    required String flagKey,
    required double defaultValue,
    required ValueWidgetBuilder<double> builder,
    Widget? child,
  }) =>
      ObservedFlagBuilder<double>(
        key: key,
        clientIdentity: client,
        flagKey: flagKey,
        defaultValue: defaultValue,
        create: () => client.observeNumber(flagKey, defaultValue),
        unchangedDefault: (a, b) => a == b || (a.isNaN && b.isNaN),
        builder: builder,
        child: child,
      );

  /// Builds from a JSON flag. The value is a decoded, deeply unmodifiable Dart
  /// structure
  static Widget jsonFlag({
    Key? key,
    required CoproductClient client,
    required String flagKey,
    required Object? defaultValue,
    required ValueWidgetBuilder<Object?> builder,
    Widget? child,
  }) =>
      ObservedFlagBuilder<Object?>(
        key: key,
        clientIdentity: client,
        flagKey: flagKey,
        defaultValue: defaultValue,
        create: () => client.observeJson(flagKey, defaultValue),
        // Defaults are compared the way the observation resolves them, so two
        // objects that encode to the same document are one default
        unchangedDefault: jsonDefaultsEqual,
        builder: builder,
        child: child,
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
