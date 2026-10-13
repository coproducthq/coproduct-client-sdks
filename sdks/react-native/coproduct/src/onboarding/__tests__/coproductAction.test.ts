import { parseCoproductAction } from '../coproductAction';

describe('parseCoproductAction', () => {
  it('parses requestPermission', () => {
    const action = parseCoproductAction(
      'coproduct-action:requestPermission?permission=notifications'
    );
    expect(action).toEqual({
      type: 'requestPermission',
      permission: 'notifications',
    });
  });

  it('parses openUrl', () => {
    const action = parseCoproductAction(
      'coproduct-action:openUrl?url=https%3A%2F%2Fexample.com'
    );
    expect(action).toEqual({ type: 'openUrl', url: 'https://example.com' });
  });

  it('parses dismiss and complete', () => {
    expect(parseCoproductAction('coproduct-action:dismiss')).toEqual({
      type: 'dismiss',
    });
    expect(parseCoproductAction('coproduct-action:complete')).toEqual({
      type: 'complete',
    });
  });

  it('parses showPaywall', () => {
    const action = parseCoproductAction(
      'coproduct-action:showPaywall?paywallId=premium_offer'
    );
    expect(action).toEqual({ type: 'showPaywall', paywallId: 'premium_offer' });
  });

  it('parses track with the JSON-encoded answers payload', () => {
    const answers = { goal: ['lose_weight'] };
    const url = `coproduct-action:track?event=action_tapped&screenId=goal&answers=${encodeURIComponent(
      JSON.stringify(answers)
    )}`;
    const action = parseCoproductAction(url);
    expect(action).toEqual({
      type: 'track',
      event: 'action_tapped',
      screenId: 'goal',
      answers: { goal: ['lose_weight'] },
    });
  });

  it('returns undefined for a non-coproduct-action URL', () => {
    expect(parseCoproductAction('https://example.com')).toBeUndefined();
  });

  it('parses request with operation, requestId, and param_-prefixed params', () => {
    const action = parseCoproductAction(
      'coproduct-action:request?operation=requestPermission&requestId=abc123&param_permission=camera'
    );
    expect(action).toEqual({
      type: 'request',
      operation: 'requestPermission',
      requestId: 'abc123',
      params: { permission: 'camera' },
    });
  });

  it('parses request with no params at all', () => {
    const action = parseCoproductAction(
      'coproduct-action:request?operation=fetchPlan&requestId=xyz'
    );
    expect(action).toEqual({
      type: 'request',
      operation: 'fetchPlan',
      requestId: 'xyz',
      params: {},
    });
  });
});
