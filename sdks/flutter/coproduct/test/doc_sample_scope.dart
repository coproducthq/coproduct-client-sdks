import 'package:coproduct/coproduct.dart';
import 'package:flutter/widgets.dart';

/// The client-access recipe from doc/state_management_recipes.md, compiled here
/// so the documented sample cannot rot. The doc and this file are held
/// identical by doc_samples_test.dart
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
