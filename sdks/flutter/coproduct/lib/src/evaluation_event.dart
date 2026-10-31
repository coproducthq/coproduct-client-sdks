import 'rust/api.dart' as frb;

/// Why an evaluation resolved the way it did, on [EvaluationEvent.reason].
enum EvaluationReason {
  /// A targeting rule matched. [EvaluationEvent.ruleId] identifies which one
  targetingMatch,

  /// No targeting rule matched, so the flag's fallthrough value was served
  fallthrough,

  /// The flag is switched off or paused, so its off value was served
  off,

  /// The flag's prerequisite was not met, so its off value was served
  prerequisiteFailed,

  /// The evaluation failed. [EvaluationEvent.errorCode] carries a
  /// machine-readable reason, and [EvaluationEvent.value] is the caller's
  /// default value
  error,
}

/// The getter type that triggered an evaluation, on [EvaluationEvent.flagType].
enum FlagType { bool, string, int, number, json, stringList, numberList }

/// A flag's value as it appears on an [EvaluationEvent]: a bool, string, int,
/// number, or encoded JSON text.
///
/// Create one with a factory constructor only for a test double; a real
/// [EvaluationEvent] always carries one produced by the SDK. [FlagValue.json]
/// carries encoded JSON text rather than a decoded Dart value, matching
/// `CoproductClient.getJson`'s backend seam
sealed class FlagValue {
  /// Base constructor for the value kinds. Use a factory constructor instead
  const FlagValue();

  /// A boolean value
  const factory FlagValue.bool(bool value) = BoolFlagValue;

  /// A string value
  const factory FlagValue.string(String value) = StringFlagValue;

  /// An integer value
  const factory FlagValue.int(int value) = IntFlagValue;

  /// A numeric value
  const factory FlagValue.number(double value) = NumberFlagValue;

  /// A JSON value, carried as encoded JSON text rather than a decoded Dart
  /// value
  const factory FlagValue.json(String value) = JsonFlagValue;

  /// A list of string values
  const factory FlagValue.stringList(List<String> value) = StringListFlagValue;

  /// A list of numeric values
  const factory FlagValue.numberList(List<double> value) = NumberListFlagValue;
}

final class BoolFlagValue extends FlagValue {
  const BoolFlagValue(this.value);
  final bool value;

  @override
  bool operator ==(Object other) =>
      other is BoolFlagValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class StringFlagValue extends FlagValue {
  const StringFlagValue(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is StringFlagValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class IntFlagValue extends FlagValue {
  const IntFlagValue(this.value);
  final int value;

  @override
  bool operator ==(Object other) =>
      other is IntFlagValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class NumberFlagValue extends FlagValue {
  const NumberFlagValue(this.value);
  final double value;

  @override
  bool operator ==(Object other) =>
      other is NumberFlagValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class JsonFlagValue extends FlagValue {
  const JsonFlagValue(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is JsonFlagValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class StringListFlagValue extends FlagValue {
  const StringListFlagValue(this.value);
  final List<String> value;

  @override
  bool operator ==(Object other) =>
      other is StringListFlagValue && _listEquals(other.value, value);

  @override
  int get hashCode => Object.hashAll(value);
}

final class NumberListFlagValue extends FlagValue {
  const NumberListFlagValue(this.value);
  final List<double> value;

  @override
  bool operator ==(Object other) =>
      other is NumberListFlagValue && _listEquals(other.value, value);

  @override
  int get hashCode => Object.hashAll(value);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One flag evaluation, delivered to the callback registered with
/// `CoproductClient.setEvaluationListener`.
///
/// Mirrors the evaluation analytics record the other Coproduct SDKs expose,
/// so you can forward it to your own analytics pipeline
final class EvaluationEvent {
  const EvaluationEvent({
    required this.flagKey,
    required this.flagType,
    required this.value,
    required this.defaultValue,
    this.variant,
    required this.reason,
    this.ruleId,
    this.errorCode,
    required this.evaluatedAt,
  });

  /// The key of the flag that was evaluated
  final String flagKey;

  /// The getter type that triggered this evaluation
  final FlagType flagType;

  /// The value the evaluation resolved to
  final FlagValue value;

  /// The default value the caller passed to the getter
  final FlagValue defaultValue;

  /// The name of the matched targeting rule's variant, when the flag defines
  /// named variants and one matched
  final String? variant;

  /// Why the evaluation resolved the way it did
  final EvaluationReason reason;

  /// The id of the targeting rule that matched, set only when [reason] is
  /// [EvaluationReason.targetingMatch]
  final String? ruleId;

  /// A machine-readable error code, set only when [reason] is
  /// [EvaluationReason.error]
  final String? errorCode;

  /// When the evaluation happened, as an RFC 3339 timestamp string. Kept as
  /// text rather than parsed into a `DateTime`, matching every other
  /// Coproduct SDK's evaluation event
  final String evaluatedAt;

  @override
  int get hashCode => Object.hash(
    flagKey,
    flagType,
    value,
    defaultValue,
    variant,
    reason,
    ruleId,
    errorCode,
    evaluatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is EvaluationEvent &&
      other.flagKey == flagKey &&
      other.flagType == flagType &&
      other.value == value &&
      other.defaultValue == defaultValue &&
      other.variant == variant &&
      other.reason == reason &&
      other.ruleId == ruleId &&
      other.errorCode == errorCode &&
      other.evaluatedAt == evaluatedAt;
}

/// Converts a generated flag value into the public [FlagValue]. Package-private
/// so the generated type never reaches the public API
FlagValue flagValueFromFrb(frb.FrbFlagValue value) => switch (value) {
  frb.FrbFlagValue_Bool(:final value) => FlagValue.bool(value),
  frb.FrbFlagValue_String(:final value) => FlagValue.string(value),
  frb.FrbFlagValue_Int(:final value) => FlagValue.int(value),
  frb.FrbFlagValue_Number(:final value) => FlagValue.number(value),
  frb.FrbFlagValue_Json(:final value) => FlagValue.json(value),
  frb.FrbFlagValue_StringList(:final value) => FlagValue.stringList(value),
  frb.FrbFlagValue_NumberList(:final value) => FlagValue.numberList(value),
};

/// Converts a generated evaluation reason into the public [EvaluationReason]
EvaluationReason evaluationReasonFromFrb(frb.FrbEvaluationReason reason) =>
    switch (reason) {
      frb.FrbEvaluationReason.targetingMatch =>
        EvaluationReason.targetingMatch,
      frb.FrbEvaluationReason.fallthrough => EvaluationReason.fallthrough,
      frb.FrbEvaluationReason.off => EvaluationReason.off,
      frb.FrbEvaluationReason.prerequisiteFailed =>
        EvaluationReason.prerequisiteFailed,
      frb.FrbEvaluationReason.error => EvaluationReason.error,
    };

/// Converts a generated flag type into the public [FlagType]
FlagType flagTypeFromFrb(frb.FrbFlagType type) => switch (type) {
  frb.FrbFlagType.bool => FlagType.bool,
  frb.FrbFlagType.string => FlagType.string,
  frb.FrbFlagType.int => FlagType.int,
  frb.FrbFlagType.number => FlagType.number,
  frb.FrbFlagType.json => FlagType.json,
  frb.FrbFlagType.stringList => FlagType.stringList,
  frb.FrbFlagType.numberList => FlagType.numberList,
};

/// Converts a generated evaluation event into the public [EvaluationEvent].
/// Package-private so the generated type never reaches the public API
EvaluationEvent evaluationEventFromFrb(frb.FrbEvaluationEvent event) =>
    EvaluationEvent(
      flagKey: event.flagKey,
      flagType: flagTypeFromFrb(event.flagType),
      value: flagValueFromFrb(event.value),
      defaultValue: flagValueFromFrb(event.defaultValue),
      variant: event.variant,
      reason: evaluationReasonFromFrb(event.reason),
      ruleId: event.ruleId,
      errorCode: event.errorCode,
      evaluatedAt: event.evaluatedAt,
    );
