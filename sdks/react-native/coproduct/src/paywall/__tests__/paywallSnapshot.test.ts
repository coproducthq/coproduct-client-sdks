import { parsePaywallSnapshot } from '../models/paywallSnapshot';

describe('parsePaywallSnapshot', () => {
  it('parses a full snapshot, including packages', () => {
    const snapshot = parsePaywallSnapshot({
      paywallId: 'p-1',
      version: 2,
      templateType: 'hero_single_offer',
      content: {
        offeringKey: 'default',
        ctas: [
          { packageKey: 'monthly', label: 'Subscribe monthly' },
          { packageKey: 'annual', label: 'Subscribe annually' },
        ],
        html: '<section><h1>Go Premium</h1></section>',
      },
      packages: {
        monthly: { iosProductId: 'premium_monthly' },
        annual: {
          iosProductId: 'premium_annual',
          androidProductId: 'premium_annual_android',
        },
        points_pack: {
          iosProductId: 'points_pack_300',
          kind: 'consumable',
        },
      },
      html: '<section><h1>Go Premium</h1></section>',
    });

    expect(snapshot.paywallId).toBe('p-1');
    expect(snapshot.version).toBe(2);
    expect(snapshot.templateType).toBe('hero_single_offer');
    expect(snapshot.content.offeringKey).toBe('default');
    expect(snapshot.content.html).toBe(
      '<section><h1>Go Premium</h1></section>'
    );
    expect(snapshot.content.ctas).toHaveLength(2);
    expect(snapshot.content.ctas[0]?.packageKey).toBe('monthly');
    expect(snapshot.content.ctas[0]?.label).toBe('Subscribe monthly');
    expect(snapshot.packages.monthly?.iosProductId).toBe('premium_monthly');
    expect(snapshot.packages.annual?.androidProductId).toBe(
      'premium_annual_android'
    );
    expect(snapshot.html).toBe('<section><h1>Go Premium</h1></section>');
    // A package with no kind on the wire defaults to subscription,
    // preserving this feature's original subscription-only behavior
    expect(snapshot.packages.monthly?.kind).toBe('subscription');
    expect(snapshot.packages.points_pack?.kind).toBe('consumable');
  });

  it('parses a snapshot with an empty packages map', () => {
    const snapshot = parsePaywallSnapshot({
      paywallId: 'p-1',
      version: 1,
      templateType: 'hero_single_offer',
      content: {
        offeringKey: 'default',
        ctas: [{ packageKey: 'monthly', label: 'Subscribe' }],
        html: '<section></section>',
      },
      packages: {},
      html: '<section></section>',
    });

    expect(Object.keys(snapshot.packages)).toHaveLength(0);
  });
});
