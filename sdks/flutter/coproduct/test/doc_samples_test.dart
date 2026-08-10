import 'dart:io';

import 'package:coproduct/coproduct.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doc_sample_scope.dart';

void main() {
  test('the recipes doc exists and the README points at it', () {
    expect(File('doc/state_management_recipes.md').existsSync(), isTrue);
    expect(File('README.md').readAsStringSync(),
        contains('doc/state_management_recipes.md'),
        reason: 'a recipe nobody can find is not documentation');
  });

  test('the documented client-access sample is the compiled one', () {
    // The whole class body is compared, not selected lines, so the doc cannot
    // carry a method that differs from the one this package compiles
    final doc = File('doc/state_management_recipes.md').readAsStringSync();
    final compiled = File('test/doc_sample_scope.dart').readAsStringSync();
    final documented = _dartBlockContaining(doc, 'class CoproductScope');
    expect(documented, isNotEmpty,
        reason: 'the doc must carry a Dart block declaring CoproductScope');
    expect(compiled, contains(documented),
        reason: 'the documented sample and the compiled sample have diverged');
  });

  testWidgets('the sample resolves the nearest scope', (tester) async {
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
        reason: 'the nearest scope wins, not the outermost');
  });

  testWidgets('the sample fails loudly when no scope is above it',
      (tester) async {
    await tester.pumpWidget(Builder(
      builder: (context) {
        expect(() => CoproductScope.of(context), throwsAssertionError,
            reason: 'a missing scope must assert, not return null');
        return const SizedBox.shrink();
      },
    ));
  });

  testWidgets('the sample notifies dependents only when the client changes',
      (tester) async {
    final first = _FakeClient();
    final second = _FakeClient();
    _dependentBuilds = 0;

    // The dependent is a const widget, so rebuilding the scope does not
    // rebuild it on its own. That isolates updateShouldNotify: a rebuild here
    // happens only because the inherited widget said the value changed
    Widget host(CoproductClient client) =>
        CoproductScope(client: client, child: const _Dependent());

    await tester.pumpWidget(host(first));
    expect(_dependentBuilds, 1);

    await tester.pumpWidget(host(first));
    expect(_dependentBuilds, 1,
        reason: 'updateShouldNotify must be false for one client');

    await tester.pumpWidget(host(second));
    expect(_dependentBuilds, 2,
        reason: 'a different client must notify dependents');
  });
}

int _dependentBuilds = 0;

/// Const so the framework reuses its element across a scope rebuild, leaving
/// the inherited notification as the only reason it would build again
class _Dependent extends StatelessWidget {
  const _Dependent();

  @override
  Widget build(BuildContext context) {
    CoproductScope.of(context);
    _dependentBuilds += 1;
    return const SizedBox.shrink();
  }
}

/// The first fenced Dart block in [markdown] that contains [needle], with the
/// fences stripped
String _dartBlockContaining(String markdown, String needle) {
  final blocks = RegExp(r'^```dart\n(.*?)^```$', multiLine: true, dotAll: true)
      .allMatches(markdown)
      .map((match) => match.group(1)!)
      .where((block) => block.contains(needle));
  return blocks.isEmpty ? '' : blocks.first;
}

/// Only identity matters for a scope, so nothing has to be implemented
class _FakeClient implements CoproductClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
