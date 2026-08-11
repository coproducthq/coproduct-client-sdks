import 'package:coproduct/coproduct.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolves the nearest scope rather than the outermost',
      (tester) async {
    final outer = _FakeClient();
    final inner = _FakeClient();
    late CoproductClient fromOuter;
    late CoproductClient fromInner;

    await tester.pumpWidget(CoproductScope(
      client: outer,
      child: Builder(builder: (context) {
        fromOuter = CoproductScope.of(context);
        return CoproductScope(
          client: inner,
          child: Builder(builder: (context) {
            fromInner = CoproductScope.of(context);
            return const SizedBox.shrink();
          }),
        );
      }),
    ));

    expect(identical(fromOuter, outer), isTrue);
    expect(identical(fromInner, inner), isTrue,
        reason: 'the nearest scope wins');
  });

  testWidgets('throws a diagnostic error when no scope is above',
      (tester) async {
    Object? thrown;

    // Caught here rather than allowed to escape, because an exception thrown
    // during build would otherwise be reported by the test framework as a
    // widget error and this test wants to inspect the message
    await tester.pumpWidget(Builder(builder: (context) {
      try {
        CoproductScope.of(context);
      } catch (error) {
        thrown = error;
      }
      return const SizedBox.shrink();
    }));

    expect(thrown, isA<FlutterError>());
    final message = (thrown! as FlutterError).message;
    expect(message, contains('CoproductScope'),
        reason: 'the message must name the widget to install');
    expect(message, contains('client:'),
        reason: 'and the other remedy, passing a client explicitly');
  });

  testWidgets('notifies dependents only when the client changes',
      (tester) async {
    final first = _FakeClient();
    final second = _FakeClient();
    _dependentBuilds = 0;

    // The dependent is const, so the framework reuses its element across a
    // scope rebuild. That leaves the inherited notification as the only reason
    // it would build again, which is what isolates updateShouldNotify
    Widget host(CoproductClient client) =>
        CoproductScope(client: client, child: const _Dependent());

    await tester.pumpWidget(host(first));
    expect(_dependentBuilds, 1);

    await tester.pumpWidget(host(first));
    expect(_dependentBuilds, 1,
        reason: 'the same client is not a change');

    await tester.pumpWidget(host(second));
    expect(_dependentBuilds, 2,
        reason: 'a different client must notify dependents');
  });
}

int _dependentBuilds = 0;

class _Dependent extends StatelessWidget {
  const _Dependent();

  @override
  Widget build(BuildContext context) {
    CoproductScope.of(context);
    _dependentBuilds += 1;
    return const SizedBox.shrink();
  }
}

/// Only identity matters to a scope, so nothing has to be implemented
class _FakeClient implements CoproductClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
