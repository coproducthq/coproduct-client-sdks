import 'flag_table.dart';

/// Builds the GET /v1/snapshot response body from the canonical flag table.
/// The envelope omits the top-level sdkContext key so a server timezone cannot
/// satisfy the timezone is_set flag. The expected platform and the app version
/// and build are substituted into the value-equality rules.
///
/// [version] is the snapshot version the envelope advertises, and [omitFlags]
/// drops those flag keys from the served snapshot so a test can prove a flag
/// leaving the snapshot resolves to the caller's default.
Map<String, Object?> buildSnapshotEnvelope({
  required String expectedPlatform,
  required String appVersion,
  required String appBuild,
  required String generatedAt,
  int version = 1,
  Set<String> omitFlags = const {},
}) {
  String substitute(String token) => switch (token) {
        kPlatformToken => expectedPlatform,
        kAppVersionToken => appVersion,
        kAppBuildToken => appBuild,
        _ => token,
      };

  Map<String, Object?> buildFlag(FlagSpec f) {
    if (f.kind == FlagKind.untargeted) {
      return {
        'key': f.key,
        'type': f.flagType,
        'isPaused': false,
        'variations': [
          {'key': 'on', 'value': f.variationTarget},
        ],
        'offVariation': 'on',
        'fallthroughVariation': 'on',
        'targetingRules': <Object?>[],
      };
    }
    return {
      'key': f.key,
      'type': f.flagType,
      'isPaused': false,
      'variations': [
        {'key': 'match', 'value': f.variationTarget},
        {'key': 'miss', 'value': f.variationMiss},
      ],
      'offVariation': 'miss',
      'fallthroughVariation': 'miss',
      'targetingRules': [
        {
          'rule_id': 'r-${f.key}',
          'condition': {
            'type': 'attribute',
            'attribute': f.attribute,
            'operator': f.operator,
            'values': [for (final v in f.values) substitute(v)],
          },
          'coverage': 10000,
          'rollout': {'type': 'variation', 'variation': 'match'},
        },
      ],
    };
  }

  return {
    'snapshot': {
      'schemaVersion': 1,
      'version': version,
      'generatedAt': generatedAt,
      'environment': <String, Object?>{},
      'flags': [
        for (final f in kFlagTable)
          if (!omitFlags.contains(f.key)) buildFlag(f),
      ],
      'segments': <Object?>[],
    },
  };
}
