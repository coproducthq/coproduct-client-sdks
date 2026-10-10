import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct/src/paywall/paywall_shell_assembler.dart';

void main() {
  test('wraps the body html and inlines the platform script', () {
    final html = PaywallShellAssembler.assemble(
      bodyHtml: '<section><h1>Go Premium</h1></section>',
      platformScriptJs: 'console.log("hi")',
    );

    expect(html, contains('<section><h1>Go Premium</h1></section>'));
    expect(html, contains('<script>console.log("hi")</script>'));
    expect(html, contains('<!doctype html>'));
  });
}
