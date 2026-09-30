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
///   // Required before initialize, which reads the app version and cache
///   // directory through platform plugins
///   WidgetsFlutterBinding.ensureInitialized();
///   final client = await Coproduct.initialize(sdkKey: 'cpk_mob_...');
///   runApp(CoproductScope(client: client, child: const MyApp()));
/// }
/// ```
///
/// [CoproductFlagBuilder] finds the client here when its `client` argument is
/// omitted, and [of] returns it for anything else, such as calling `identify`
/// after sign-in.
///
/// This scope carries a client your app already created. It does not call
/// `Coproduct.initialize` or `Coproduct.shutdown`, and it disposes no
/// observation. An app using Provider, Riverpod, or BLoC can hold the client
/// there instead and pass `client:` explicitly, and then needs no scope
final class CoproductScope extends InheritedWidget {
  /// Makes [client] available to [child] and every widget below it
  const CoproductScope({super.key, required this.client, required super.child});

  /// The client that [of] returns to every widget below this scope
  final CoproductClient client;

  /// Returns the client from the nearest [CoproductScope] above [context].
  ///
  /// The calling widget rebuilds if the scope is given a different client.
  /// Throws a [FlutterError] when no scope is above [context], in every build
  /// mode. The message names both fixes: add a scope, or pass the client
  /// explicitly
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
