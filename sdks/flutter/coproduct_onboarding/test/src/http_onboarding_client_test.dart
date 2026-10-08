import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coproduct_onboarding/src/http_onboarding_client.dart';

Map<String, dynamic> _graphJson() => {
  'startScreenId': 'start',
  'screens': [
    {
      'id': 'start',
      'html': '<p>hi</p>',
      'transitions': [],
      'defaultNext': {'type': 'complete'},
    },
  ],
};

void main() {
  test(
    'fetchOnboardingFlow GETs this environment\'s latest content URL and parses the graph',
    () async {
      final client = HttpOnboardingClient(
        envSlug: 'production',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://content.coproduct.app/onboarding/flow-1/production/latest.json',
          );
          return http.Response(jsonEncode(_graphJson()), 200);
        }),
      );

      final graph = await client.fetchOnboardingFlow('flow-1');
      expect(graph, isNotNull);
      expect(graph!.startScreenId, 'start');
      expect(graph.screens, hasLength(1));
    },
  );

  test(
    'fetchOnboardingFlow scopes the URL to the configured environment',
    () async {
      final client = HttpOnboardingClient(
        envSlug: 'staging',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/onboarding/flow-1/staging/latest.json');
          return http.Response(jsonEncode(_graphJson()), 200);
        }),
      );

      await client.fetchOnboardingFlow('flow-1');
    },
  );

  test(
    'fetchOnboardingFlow returns null on a 404 -- not deployed to this environment yet',
    () async {
      final client = HttpOnboardingClient(
        envSlug: 'production',
        httpClient: MockClient(
          (request) async => http.Response('not found', 404),
        ),
      );

      expect(await client.fetchOnboardingFlow('missing'), isNull);
    },
  );

  test(
    'fetchOnboardingFlow returns null on a non-2xx, non-404 response',
    () async {
      final client = HttpOnboardingClient(
        envSlug: 'production',
        httpClient: MockClient(
          (request) async => http.Response('server error', 500),
        ),
      );

      expect(await client.fetchOnboardingFlow('flow-1'), isNull);
    },
  );

  test(
    'fetchOnboardingFlow returns null when the response body is not valid JSON',
    () async {
      final client = HttpOnboardingClient(
        envSlug: 'production',
        httpClient: MockClient(
          (request) async => http.Response('not json', 200),
        ),
      );

      expect(await client.fetchOnboardingFlow('flow-1'), isNull);
    },
  );

  test(
    'fetchOnboardingFlow returns null when the underlying request throws',
    () async {
      final client = HttpOnboardingClient(
        envSlug: 'production',
        httpClient: MockClient(
          (request) async => throw Exception('connection failed'),
        ),
      );

      expect(await client.fetchOnboardingFlow('flow-1'), isNull);
    },
  );
}
