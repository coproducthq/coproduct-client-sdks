import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_paywall/src/models/paywall_snapshot.dart';

void main() {
  test('parses a full snapshot, including packages', () {
    final snapshot = PaywallSnapshot.fromJson({
      'paywallId': 'p-1',
      'version': 2,
      'templateType': 'hero_single_offer',
      'content': {
        'headline': 'Go Premium',
        'body': 'Unlock everything',
        'imageAssetId': 'img-1',
        'offeringKey': 'default',
        'ctas': [
          {'packageKey': 'monthly', 'label': 'Subscribe monthly'},
          {'packageKey': 'annual', 'label': 'Subscribe annually'},
        ],
      },
      'packages': {
        'monthly': {'iosProductId': 'premium_monthly'},
        'annual': {'iosProductId': 'premium_annual', 'androidProductId': 'premium_annual_android'},
      },
      'html': '<section></section>',
    });

    expect(snapshot.paywallId, 'p-1');
    expect(snapshot.version, 2);
    expect(snapshot.templateType, 'hero_single_offer');
    expect(snapshot.content.headline, 'Go Premium');
    expect(snapshot.content.body, 'Unlock everything');
    expect(snapshot.content.imageAssetId, 'img-1');
    expect(snapshot.content.offeringKey, 'default');
    expect(snapshot.content.ctas, hasLength(2));
    expect(snapshot.content.ctas[0].packageKey, 'monthly');
    expect(snapshot.content.ctas[0].label, 'Subscribe monthly');
    expect(snapshot.packages['monthly']!.iosProductId, 'premium_monthly');
    expect(snapshot.packages['annual']!.androidProductId, 'premium_annual_android');
    expect(snapshot.html, '<section></section>');
  });

  test('parses a snapshot with an empty packages map and no optional content fields', () {
    final snapshot = PaywallSnapshot.fromJson({
      'paywallId': 'p-1',
      'version': 1,
      'templateType': 'hero_single_offer',
      'content': {
        'headline': 'Go Premium',
        'offeringKey': 'default',
        'ctas': [{'packageKey': 'monthly', 'label': 'Subscribe'}],
      },
      'packages': <String, dynamic>{},
      'html': '<section></section>',
    });

    expect(snapshot.content.body, isNull);
    expect(snapshot.content.imageAssetId, isNull);
    expect(snapshot.packages, isEmpty);
  });
}
