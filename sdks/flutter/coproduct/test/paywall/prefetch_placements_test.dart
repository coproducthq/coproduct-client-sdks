import 'package:coproduct/paywall.dart';
import 'package:flutter_test/flutter_test.dart';

PaywallSnapshot snap(String id) => PaywallSnapshot(
      paywallId: id, version: 1, templateType: 't',
      content: const PaywallContent(offeringKey: 'default', ctas: [], html: ''),
      packages: const {}, html: '',
    );

class _FakeReader implements FlagReader {
  @override
  String getString(String key, {required String defaultValue}) =>
      const {'f.paid': 'pw1', 'f.also': 'pw1', 'f.empty': ''}[key] ?? defaultValue;
}

class _RecordingPaywallClient implements PaywallClient {
  final List<String> fetched = [];
  @override
  Future<PaywallSnapshot?> fetchPaywall(String paywallId) async {
    fetched.add(paywallId);
    return snap(paywallId);
  }

  @override
  Future<List<Entitlement>> recordPurchase({
    required String appUserId, required String platform,
    required String storeProductId, required String storeTransactionId,
    required DateTime purchaseDate, DateTime? expiresDate,
  }) async => const [];
  @override
  Future<List<Entitlement>> getEntitlements(String appUserId) async => const [];
  @override
  Future<void> identify({required String appUserId, required String targetingKey}) async {}
}

void main() {
  test('prefetchPlacements resolves keys, warms each, skips empty, dedups', () async {
    final client = _RecordingPaywallClient();
    await CoproductPaywall.prefetchPlacements(
      client: _FakeReader(),
      flagKeys: const ['f.paid', 'f.also', 'f.empty'],
      sdkKey: 'cpk_test',
      envSlug: 'production',
      paywallClient: client,
    );
    expect(client.fetched, ['pw1']);
    final served = await snapshotCache.resolve(
      snapshotCacheKey('pw1', 'production'),
      () async => null,
    );
    expect(served?.paywallId, 'pw1');
  });
}
