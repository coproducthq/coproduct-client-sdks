import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct/src/paywall/intro_offer_label.dart';

void main() {
  group('composeIntroLabel', () {
    test('composes a free-trial label', () {
      expect(
        composeIntroLabel(
          kind: IntroOfferKind.freeTrial,
          offerPeriod: '7 days',
          offerPrice: '',
          regularPrice: '\$39.99/yr',
        ),
        '7 days free, then \$39.99/yr',
      );
    });

    test('composes a pay-up-front label', () {
      expect(
        composeIntroLabel(
          kind: IntroOfferKind.payUpFront,
          offerPeriod: '3 months',
          offerPrice: '\$0.99',
          regularPrice: '\$9.99/mo',
        ),
        '\$0.99 for 3 months, then \$9.99/mo',
      );
    });

    test('composes a pay-as-you-go label', () {
      expect(
        composeIntroLabel(
          kind: IntroOfferKind.payAsYouGo,
          offerPeriod: '2 months',
          offerPrice: '\$1.99',
          regularPrice: '\$9.99/mo',
        ),
        '\$1.99 for 2 months, then \$9.99/mo',
      );
    });
  });
}
