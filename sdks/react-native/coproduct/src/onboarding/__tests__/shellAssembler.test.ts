import { assembleShell } from '../shellAssembler';
import { parseOnboardingFlowGraph } from '../models/onboardingFlowGraph';

describe('assembleShell', () => {
  it('wraps every screen fragment in a data-screen-id section', () => {
    const graph = parseOnboardingFlowGraph({
      startScreenId: 'welcome',
      screens: [
        { id: 'welcome', html: '<p>Hi</p>', transitions: [], defaultNext: { type: 'complete' } },
        { id: 'goal', html: '<p>?</p>', transitions: [], defaultNext: { type: 'complete' } },
      ],
    });

    const html = assembleShell({
      graph,
      sdkContextAttributes: { platform: 'ios' },
      sdkContextSegmentKeys: new Set(['power-users']),
      initialAnswers: {},
      initialScreenId: 'welcome',
      platformScriptJs: '/* script */',
    });

    // Every section starts hidden -- the platform script reveals the
    // current screen on load, avoiding a flash of every screen at once
    expect(html).toContain('<section data-screen-id="welcome" hidden>');
    expect(html).toContain('<p>Hi</p>');
    expect(html).toContain('<section data-screen-id="goal" hidden>');
    expect(html).toContain('/* script */');
  });

  it('embeds the injected data blob as inert JSON, escaping </script sequences', () => {
    const graph = parseOnboardingFlowGraph({
      startScreenId: 'welcome',
      screens: [{ id: 'welcome', html: '<p>Hi</p>', transitions: [], defaultNext: { type: 'complete' } }],
    });

    const html = assembleShell({
      graph,
      // Device attribute values and in-flow answers are arbitrary strings
      // that never go through server-side HTML sanitization (unlike a
      // screen's own html) -- this is the payload path the escaping guards
      sdkContextAttributes: { evil: '</script><script>alert(1)</script>' },
      sdkContextSegmentKeys: new Set(),
      initialAnswers: {},
      initialScreenId: 'welcome',
      platformScriptJs: '',
    });

    expect(html).not.toContain('</script><script>alert');
    expect(html).toContain('alert(1)');
  });
});
