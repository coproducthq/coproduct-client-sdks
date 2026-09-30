// Widget tests for the Coproduct Flutter example. A plain `flutter test` runs
// without the native FRB bridge, so these assert the first frame, before
// initialize resolves, rather than any flag read that would cross the bridge.
// integration_test covers the on-device behavior

import 'package:flutter_test/flutter_test.dart';

import 'package:coproduct_example/main.dart';

// A synthetic key, valid in format only, so the not-ready path reaches
// initialize the way a real key does
const _syntheticKey = 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww';

void main() {
  testWidgets('shows the setup message when no key was passed',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(sdkKey: ''));

    expect(find.textContaining('--dart-define=COPRODUCT_SDK_KEY='),
        findsOneWidget);
    expect(find.text('SDK ready: no'), findsNothing);
  });

  testWidgets('renders the not-ready shell before initialize resolves',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(sdkKey: _syntheticKey));

    // The shell renders immediately and the scope is installed only once
    // initialize returns, so the first frame shows the not-ready indicator
    expect(find.text('SDK ready: no'), findsOneWidget);
  });
}
