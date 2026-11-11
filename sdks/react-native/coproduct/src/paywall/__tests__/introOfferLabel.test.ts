import { composeIntroLabel } from '../introOfferLabel';

describe('composeIntroLabel', () => {
  it('composes a free-trial label', () => {
    expect(
      composeIntroLabel({ kind: 'free_trial', offerPeriod: '7 days', offerPrice: '', regularPrice: '$39.99/yr' })
    ).toBe('7 days free, then $39.99/yr');
  });

  it('composes a pay-up-front label', () => {
    expect(
      composeIntroLabel({ kind: 'pay_up_front', offerPeriod: '3 months', offerPrice: '$0.99', regularPrice: '$9.99/mo' })
    ).toBe('$0.99 for 3 months, then $9.99/mo');
  });

  it('composes a pay-as-you-go label', () => {
    expect(
      composeIntroLabel({ kind: 'pay_as_you_go', offerPeriod: '2 months', offerPrice: '$1.99', regularPrice: '$9.99/mo' })
    ).toBe('$1.99 for 2 months, then $9.99/mo');
  });
});
