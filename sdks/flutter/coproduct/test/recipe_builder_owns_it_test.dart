import 'package:coproduct/coproduct.dart';
import 'package:coproduct/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compiles and runs Recipe 1 from doc/state_management_recipes.md verbatim, so
/// a documented pattern is shown to work rather than only to read well. The
/// zero-dependency recipes are the ones tested here: compiling the Provider,
/// Riverpod, or BLoC recipes would add those packages as dev dependencies of the
/// SDK for the sake of a documentation example
void main() {
  testWidgets('Recipe 1: the builder owns the observation', (tester) async {
    final harness = CoproductTestHarness()..setBool('new-checkout', false);
    addTearDown(harness.shutdown);

    await tester.pumpWidget(MaterialApp(
      home: CoproductScope(
        client: harness.client,
        child: CoproductFlagBuilder.boolFlag(
          flagKey: 'new-checkout',
          defaultValue: false,
          builder: (context, enabled, child) =>
              enabled ? const NewCheckout() : const OldCheckout(),
        ),
      ),
    ));

    expect(find.byType(OldCheckout), findsOneWidget);

    harness.setBool('new-checkout', true);
    await tester.pumpAndSettle();
    expect(find.byType(NewCheckout), findsOneWidget);

    // The recipe's promise: the builder disposes the observation on unmount, so
    // the test needs no disposal of its own
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.byType(NewCheckout), findsNothing);
  });
}

class NewCheckout extends StatelessWidget {
  const NewCheckout({super.key});
  @override
  Widget build(BuildContext context) => const Text('new');
}

class OldCheckout extends StatelessWidget {
  const OldCheckout({super.key});
  @override
  Widget build(BuildContext context) => const Text('old');
}
