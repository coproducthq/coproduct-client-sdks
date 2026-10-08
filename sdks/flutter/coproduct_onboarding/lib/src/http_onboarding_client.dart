import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/onboarding_flow_graph.dart';

/// Fetches an onboarding flow's graph directly from the R2-backed content
/// CDN, bypassing the edge-worker round trip. An optional alternative
/// content source for CoproductClient's fetchOnboardingFlow method -- a
/// host's adapter can delegate to this class for that one method while
/// still implementing flag resolution and sdk context itself, since this
/// class knows nothing about either.
///
/// [envSlug] identifies which environment's content to fetch. The base
/// SDK's sdk key already resolves to one environment server-side, but its
/// public API does not expose that environment's slug, so this is a
/// host-supplied value, the same way coproduct_paywall's HttpPaywallClient
/// takes sdkKey and appUserId explicitly rather than deriving them.
class HttpOnboardingClient {
  HttpOnboardingClient({
    required this.envSlug,
    Uri? contentBaseUrl,
    http.Client? httpClient,
  }) : contentBaseUrl =
           contentBaseUrl ?? Uri.parse('https://content.coproduct.app'),
       _client = httpClient ?? http.Client();

  final String envSlug;
  final Uri contentBaseUrl;
  final http.Client _client;

  /// GET {contentBaseUrl}/onboarding/{flowId}/{envSlug}/latest.json.
  /// Returns null on any failure -- not deployed to this environment yet
  /// (404), a transport failure, or an unparseable body -- matching
  /// CoproductClient.fetchOnboardingFlow's documented contract that a host
  /// adapter decides the fallback, not this class.
  Future<OnboardingFlowGraph?> fetchOnboardingFlow(String flowId) async {
    final uri = contentBaseUrl.replace(
      path: '/onboarding/$flowId/$envSlug/latest.json',
    );
    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (_) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    try {
      return OnboardingFlowGraph.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
