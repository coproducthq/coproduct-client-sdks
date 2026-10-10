import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/entitlement.dart';
import 'models/paywall_snapshot.dart';
import 'paywall_client.dart';

/// package:http-backed PaywallClient. Makes its own requests rather than
/// reusing the base coproduct package's internal transport, which has no
/// public accessor for the sdk key or a request client (checked:
/// sdks/flutter/coproduct/lib/src/coproduct_client.dart and
/// lib/src/host.dart keep sdkKey entirely in src/). sdkKey is the same
/// string the host app already passed to Coproduct.initialize(sdkKey:).
class HttpPaywallClient implements PaywallClient {
  HttpPaywallClient({
    required this.sdkKey,
    this.envSlug,
    Uri? edgeBaseUrl,
    Uri? apiBaseUrl,
    Uri? contentBaseUrl,
    http.Client? httpClient,
  }) : edgeBaseUrl = edgeBaseUrl ?? Uri.parse('https://sdk.coproduct.app'),
       apiBaseUrl = apiBaseUrl ?? Uri.parse('https://api.coproduct.app'),
       contentBaseUrl =
           contentBaseUrl ?? Uri.parse('https://content.coproduct.app'),
       _client = httpClient ?? http.Client();

  final String sdkKey;

  /// When set, fetchPaywall reads straight from the R2-backed content CDN
  /// instead of the edge-worker api, with no fallback between the two --
  /// matching coproduct_onboarding's HttpOnboardingClient. The base SDK's
  /// public API does not expose its resolved environment slug, so this is
  /// a host-supplied value, same as sdkKey and appUserId elsewhere in this
  /// class.
  final String? envSlug;
  final Uri edgeBaseUrl;
  final Uri apiBaseUrl;
  final Uri contentBaseUrl;
  final http.Client _client;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $sdkKey',
    'Content-Type': 'application/json',
  };

  @override
  Future<PaywallSnapshot?> fetchPaywall(String paywallId) {
    final envSlug = this.envSlug;
    return envSlug != null
        ? _fetchPaywallFromContentCdn(paywallId, envSlug)
        : _fetchPaywallFromApi(paywallId);
  }

  /// GET {contentBaseUrl}/paywalls/{paywallId}/{envSlug}/latest.json.
  /// Returns null on any failure -- not deployed to this environment yet
  /// (404), a transport failure, or an unparseable body -- the same
  /// swallow-and-return-null contract HttpOnboardingClient.fetchOnboardingFlow
  /// uses, deliberately with no fallback to the api
  Future<PaywallSnapshot?> _fetchPaywallFromContentCdn(
    String paywallId,
    String envSlug,
  ) async {
    final uri = contentBaseUrl.replace(
      path: '/paywalls/$paywallId/$envSlug/latest.json',
    );
    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (_) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    try {
      return PaywallSnapshot.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<PaywallSnapshot?> _fetchPaywallFromApi(String paywallId) async {
    final uri = edgeBaseUrl.replace(path: '/paywalls/$paywallId');
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode == 404) return null;
    _throwIfError(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PaywallSnapshot.fromJson(body['paywall'] as Map<String, dynamic>);
  }

  @override
  Future<List<Entitlement>> recordPurchase({
    required String appUserId,
    required String platform,
    required String storeProductId,
    required String storeTransactionId,
    required DateTime purchaseDate,
    DateTime? expiresDate,
  }) async {
    final uri = apiBaseUrl.replace(path: '/v1/purchases');
    final response = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'app_user_id': appUserId,
        'platform': platform,
        'store_product_id': storeProductId,
        'transaction': {
          'store_transaction_id': storeTransactionId,
          'purchase_date': purchaseDate.toUtc().toIso8601String(),
          if (expiresDate != null)
            'expires_date': expiresDate.toUtc().toIso8601String(),
        },
      }),
    );
    _throwIfError(response);
    return _entitlementsFromBody(response.body);
  }

  @override
  Future<List<Entitlement>> getEntitlements(String appUserId) async {
    final uri = apiBaseUrl.replace(
      path: '/v1/entitlements',
      queryParameters: {'appUserId': appUserId},
    );
    final response = await _client.get(uri, headers: _headers);
    _throwIfError(response);
    return _entitlementsFromBody(response.body);
  }

  @override
  Future<void> identify({
    required String appUserId,
    required String targetingKey,
  }) async {
    final uri = apiBaseUrl.replace(path: '/v1/identify');
    final response = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'app_user_id': appUserId,
        'targeting_key': targetingKey,
      }),
    );
    _throwIfError(response);
  }

  List<Entitlement> _entitlementsFromBody(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
    return (body['entitlements'] as List)
        .map((e) => Entitlement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _throwIfError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String? code;
    var message = 'Request failed with status ${response.statusCode}';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      code = body['code'] as String?;
      message = body['error'] as String? ?? message;
    } catch (_) {
      // Non-JSON error body -- keep the generic message
    }
    throw PaywallServerError(
      statusCode: response.statusCode,
      code: code,
      message: message,
    );
  }
}
