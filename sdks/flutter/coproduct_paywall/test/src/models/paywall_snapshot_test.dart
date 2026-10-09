import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_paywall/src/models/paywall_snapshot.dart';

void main() {
  test('parses a full snapshot, including packages', () {
    final snapshot = PaywallSnapshot.fromJson({
      'paywallId': 'p-1',
      'version': 2,
      'templateType': 'hero_single_offer',
      'content': {
        'offeringKey': 'default',
        'ctas': [
          {'packageKey': 'monthly', 'label': 'Subscribe monthly'},
          {'packageKey': 'annual', 'label': 'Subscribe annually'},
        ],
        'html': '<section><h1>Go Premium</h1></section>',
      },
      'packages': {
        'monthly': {'iosProductId': 'premium_monthly'},
        'annual': {
          'iosProductId': 'premium_annual',
          'androidProductId': 'premium_annual_android',
        },
      },
      'html': '<section><h1>Go Premium</h1></section>',
    });

    expect(snapshot.paywallId, 'p-1');
    expect(snapshot.version, 2);
    expect(snapshot.templateType, 'hero_single_offer');
    expect(snapshot.content.offeringKey, 'default');
    expect(snapshot.content.html, '<section><h1>Go Premium</h1></section>');
    expect(snapshot.content.ctas, hasLength(2));
    expect(snapshot.content.ctas[0].packageKey, 'monthly');
    expect(snapshot.content.ctas[0].label, 'Subscribe monthly');
    expect(snapshot.packages['monthly']!.iosProductId, 'premium_monthly');
    expect(
      snapshot.packages['annual']!.androidProductId,
      'premium_annual_android',
    );
    expect(snapshot.html, '<section><h1>Go Premium</h1></section>');
  });

  test('parses a snapshot with an empty packages map', () {
    final snapshot = PaywallSnapshot.fromJson({
      'paywallId': 'p-1',
      'version': 1,
      'templateType': 'hero_single_offer',
      'content': {
        'offeringKey': 'default',
        'ctas': [
          {'packageKey': 'monthly', 'label': 'Subscribe'},
        ],
        'html': '<section></section>',
      },
      'packages': <String, dynamic>{},
      'html': '<section></section>',
    });

    expect(snapshot.packages, isEmpty);
  });
}
