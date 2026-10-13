import { assemblePaywallShell } from '../paywallShellAssembler';

describe('assemblePaywallShell', () => {
  it('wraps the body html and inlines the platform script', () => {
    const html = assemblePaywallShell({
      bodyHtml: '<section><h1>Go Premium</h1></section>',
      platformScriptJs: 'console.log("hi")',
    });

    expect(html).toContain('<section><h1>Go Premium</h1></section>');
    expect(html).toContain('<script>console.log("hi")</script>');
    expect(html).toContain('<!doctype html>');
  });
});
