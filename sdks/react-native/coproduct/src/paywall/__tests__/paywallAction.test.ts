import { parsePaywallAction } from '../paywallAction';

describe('parsePaywallAction', () => {
  it('parses purchase with its packageKey', () => {
    const action = parsePaywallAction(
      'coproduct-action:purchase?packageKey=monthly'
    );
    expect(action).toEqual({ type: 'purchase', packageKey: 'monthly' });
  });

  it('parses restore with no params', () => {
    expect(parsePaywallAction('coproduct-action:restore')).toEqual({
      type: 'restore',
    });
  });

  it('parses dismiss', () => {
    expect(parsePaywallAction('coproduct-action:dismiss')).toEqual({
      type: 'dismiss',
    });
  });

  it('returns undefined for purchase with no packageKey', () => {
    expect(parsePaywallAction('coproduct-action:purchase')).toBeUndefined();
  });

  it('returns undefined for an unknown action', () => {
    expect(
      parsePaywallAction('coproduct-action:somethingElse')
    ).toBeUndefined();
  });

  it('returns undefined for a non-coproduct-action URL', () => {
    expect(parsePaywallAction('https://example.com')).toBeUndefined();
  });
});
