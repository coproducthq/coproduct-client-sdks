// Widget test for the Coproduct Flutter scaffold. A plain `flutter test` runs
// without the native FRB bridge, so this asserts the deterministic first frame,
// before initialize resolves, rather than any flag read that would cross the
// bridge. The on-device behavior is covered by integration_test

import 'package:flutter_test/flutter_test.dart';

import 'package:coproduct_example/main.dart';

void main() {
  testWidgets('renders the not-ready shell before initialize resolves',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // The shell renders immediately and the scope is installed only once
    // initialize returns, so the first frame shows the not-ready indicator
    expect(find.text('SDK ready: no'), findsOneWidget);
  });
}
