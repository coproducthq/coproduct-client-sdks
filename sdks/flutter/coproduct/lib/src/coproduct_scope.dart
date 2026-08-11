import 'package:flutter/widgets.dart';

// The public client type lives in the package entrypoint, which also re-exports
// this file. Importing it by package URI keeps the scope beside the API it
// serves rather than splitting the two across libraries
import 'package:coproduct/coproduct.dart';

/// Carries an initialized [CoproductClient] down the widget tree, so a widget
/// reaches it from its [BuildContext] instead of receiving it through every
/// constructor in between.
///
/// Install it once, above anything that reads a flag:
///
/// ```dart
/// Future<void> main() async {
///   // Required before initialize, which reaches platform plugins
///   WidgetsFlutterBinding.ensureInitialized();
///   final client = await Coproduct.initialize(sdkKey: 'your-key');
///   runApp(CoproductScope(client: client, child: const MyApp()));
/// }
/// ```
///
/// [CoproductFlagBuilder] finds the client here when its `client` argument is
/// omitted, and [of] returns it for anything else, such as calling `identify`
/// after a login.
///
/// This scope carries a client your app already created. It does not call
/// `Coproduct.initialize`, it does not call `Coproduct.shutdown`, and it owns
/// no observation's lifetime. An app using Provider, Riverpod, or BLoC can
/// carry the client in that instead and pass `client:` explicitly, in which
/// case no scope is needed
class CoproductScope extends InheritedWidget {
  const CoproductScope({
    super.key,
    required this.client,
    required super.child,
  });

  /// The client every descendant resolves
  final CoproductClient client;

  /// The client from the nearest enclosing [CoproductScope].
  ///
  /// Throws a [FlutterError] when no scope is above [context]. It throws in
  /// every build mode rather than asserting, so a release build reports the
  /// same diagnostic instead of an unhelpful null check
  static CoproductClient of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CoproductScope>();
    if (scope == null) {
      throw FlutterError(
        'No CoproductScope was found above this context.\n'
        'Install a CoproductScope above this widget. When using '
        'CoproductFlagBuilder, you can instead pass client: explicitly.',
      );
    }
    return scope.client;
  }

  @override
  bool updateShouldNotify(CoproductScope oldWidget) =>
      !identical(client, oldWidget.client);
}
