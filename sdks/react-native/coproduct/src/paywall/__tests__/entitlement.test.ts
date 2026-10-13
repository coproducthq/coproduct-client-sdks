import { parseEntitlement } from '../models/entitlement';

describe('parseEntitlement', () => {
  it('parses an active, renewing entitlement with an expiry', () => {
    const entitlement = parseEntitlement({
      entitlementId: 'premium',
      isActive: true,
      expiresAt: '2026-11-01T00:00:00.000Z',
      willRenew: true,
      source: 'PURCHASE',
    });

    expect(entitlement.entitlementId).toBe('premium');
    expect(entitlement.isActive).toBe(true);
    expect(entitlement.expiresAt).toEqual(new Date('2026-11-01T00:00:00.000Z'));
    expect(entitlement.willRenew).toBe(true);
    expect(entitlement.source).toBe('PURCHASE');
  });

  it('parses a never-expiring entitlement', () => {
    const entitlement = parseEntitlement({
      entitlementId: 'lifetime',
      isActive: true,
      expiresAt: null,
      willRenew: false,
      source: 'PURCHASE',
    });

    expect(entitlement.expiresAt).toBeUndefined();
  });
});
