/// The single source of truth for the acceptance fixture and the on-device test.
/// The fixture builds its snapshot from this table, and the runner projects
/// [expectedTable] to the device test, so the two cannot drift.

/// How the on-device test reads a flag.
enum GetterType { boolean, string, integer, number, json }

/// What a flag proves: an untargeted fetch control, an automatic attribute that
/// matches from initialize, or an identity attribute that flips on identify.
enum FlagKind { untargeted, auto, identity }

/// A placeholder the snapshot builder replaces with the runner-supplied value.
const String kPlatformToken = '<PLATFORM>';
const String kAppVersionToken = '<APP_VERSION>';
const String kAppBuildToken = '<APP_BUILD>';

class FlagSpec {
  const FlagSpec({
    required this.key,
    required this.flagType,
    required this.getter,
    required this.kind,
    required this.callerDefault,
    this.variationTarget,
    this.variationMiss,
    this.getterTarget,
    this.getterMiss,
    this.attribute,
    this.operator,
    this.values = const [],
  });

  final String key;
  final String flagType; // BOOL / STRING / NUMBER / JSON
  final GetterType getter;
  final FlagKind kind;
  final Object callerDefault;

  // The raw variation values stored in the snapshot. Null for the untargeted
  // fetch control, which uses [variationTarget] as its single variation
  final Object? variationTarget;
  final Object? variationMiss;

  // The values the getter is expected to return, which differ from the stored
  // variation for the truncating integer getter
  final Object? getterTarget;
  final Object? getterMiss;

  // The rule for a targeted flag. Null attribute means untargeted
  final String? attribute;
  final String? operator;
  final List<String> values;
}

const List<FlagSpec> kFlagTable = [
  FlagSpec(
    key: 'fetch-control',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.untargeted,
    variationTarget: 'fetched',
    getterTarget: 'fetched',
    callerDefault: 'unfetched',
  ),
  FlagSpec(
    key: 'auto-platform',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.auto,
    attribute: 'platform',
    operator: 'equals',
    values: [kPlatformToken],
    variationTarget: 'platform-matched',
    variationMiss: 'platform-missed',
    getterTarget: 'platform-matched',
    getterMiss: 'platform-missed',
    callerDefault: 'platform-default',
  ),
  FlagSpec(
    key: 'auto-app-version',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.auto,
    attribute: 'app_version',
    operator: 'equals',
    values: [kAppVersionToken],
    variationTarget: 'app-version-matched',
    variationMiss: 'app-version-missed',
    getterTarget: 'app-version-matched',
    getterMiss: 'app-version-missed',
    callerDefault: 'app-version-default',
  ),
  FlagSpec(
    key: 'auto-app-build',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.auto,
    attribute: 'app_build',
    operator: 'equals',
    values: [kAppBuildToken],
    variationTarget: 'app-build-matched',
    variationMiss: 'app-build-missed',
    getterTarget: 'app-build-matched',
    getterMiss: 'app-build-missed',
    callerDefault: 'app-build-default',
  ),
  FlagSpec(
    key: 'auto-os-version',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.auto,
    attribute: 'os_version',
    operator: 'is_set',
    values: [],
    variationTarget: 'os-version-present',
    variationMiss: 'os-version-missing',
    getterTarget: 'os-version-present',
    getterMiss: 'os-version-missing',
    callerDefault: 'os-version-default',
  ),
  FlagSpec(
    key: 'auto-locale',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.auto,
    attribute: 'locale',
    operator: 'is_set',
    values: [],
    variationTarget: 'locale-present',
    variationMiss: 'locale-missing',
    getterTarget: 'locale-present',
    getterMiss: 'locale-missing',
    callerDefault: 'locale-default',
  ),
  FlagSpec(
    key: 'auto-timezone',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.auto,
    attribute: 'timezone',
    operator: 'is_set',
    values: [],
    variationTarget: 'timezone-present',
    variationMiss: 'timezone-missing',
    getterTarget: 'timezone-present',
    getterMiss: 'timezone-missing',
    callerDefault: 'timezone-default',
  ),
  FlagSpec(
    key: 'identity-bool',
    flagType: 'BOOL',
    getter: GetterType.boolean,
    kind: FlagKind.identity,
    attribute: 'plan',
    operator: 'equals',
    values: ['pro'],
    variationTarget: true,
    variationMiss: false,
    getterTarget: true,
    getterMiss: false,
    callerDefault: false,
  ),
  FlagSpec(
    key: 'identity-string',
    flagType: 'STRING',
    getter: GetterType.string,
    kind: FlagKind.identity,
    attribute: 'plan',
    operator: 'equals',
    values: ['pro'],
    variationTarget: 'identity-string-matched',
    variationMiss: 'identity-string-missed',
    getterTarget: 'identity-string-matched',
    getterMiss: 'identity-string-missed',
    callerDefault: 'identity-string-default',
  ),
  FlagSpec(
    key: 'identity-int',
    flagType: 'NUMBER',
    getter: GetterType.integer,
    kind: FlagKind.identity,
    attribute: 'plan',
    operator: 'equals',
    values: ['pro'],
    variationTarget: 42.75,
    variationMiss: 0.0,
    getterTarget: 42,
    getterMiss: 0,
    callerDefault: -1,
  ),
  FlagSpec(
    key: 'identity-number',
    flagType: 'NUMBER',
    getter: GetterType.number,
    kind: FlagKind.identity,
    attribute: 'plan',
    operator: 'equals',
    values: ['pro'],
    variationTarget: 3.5,
    variationMiss: 0.0,
    getterTarget: 3.5,
    getterMiss: 0.0,
    callerDefault: -1.5,
  ),
  FlagSpec(
    key: 'identity-json',
    flagType: 'JSON',
    getter: GetterType.json,
    kind: FlagKind.identity,
    attribute: 'plan',
    operator: 'equals',
    values: ['pro'],
    variationTarget: {
      'theme': 'acceptance',
      'items': [1, 2, 3]
    },
    variationMiss: {'variant': 'missed'},
    getterTarget: {
      'theme': 'acceptance',
      'items': [1, 2, 3]
    },
    getterMiss: {'variant': 'missed'},
    callerDefault: {'caller': 'default'},
  ),
];

String _getterName(GetterType g) => switch (g) {
      GetterType.boolean => 'boolean',
      GetterType.string => 'string',
      GetterType.integer => 'integer',
      GetterType.number => 'number',
      GetterType.json => 'json',
    };

/// The per-flag expectations the runner passes to the on-device test as JSON.
/// Getter-level values, so the truncating integer getter expects 42, not 42.75.
List<Map<String, Object?>> expectedTable() => [
      for (final f in kFlagTable)
        {
          'key': f.key,
          'getter': _getterName(f.getter),
          'kind': f.kind.name,
          'callerDefault': f.callerDefault,
          'target': f.getterTarget,
          if (f.kind == FlagKind.identity) 'miss': f.getterMiss,
        },
    ];
