import 'rust/api.dart' as frb;

/// The shared marker for exceptions Coproduct throws. Catch a specific subtype
/// for a known condition, or this interface to handle any Coproduct error
abstract interface class CoproductException implements Exception {}

/// Thrown when no SDK key was supplied
final class MissingSdkKey implements CoproductException {
  const MissingSdkKey();
  @override
  bool operator ==(Object other) => other is MissingSdkKey;
  @override
  int get hashCode => (MissingSdkKey).hashCode;
  @override
  String toString() => 'A Coproduct SDK key is required';
}

/// Thrown when the SDK key prefix is not the mobile prefix. [observedPrefix] is
/// the prefix that was supplied, not the expected one
final class InvalidKeyType implements CoproductException {
  const InvalidKeyType(this.observedPrefix);
  final String observedPrefix;
  @override
  bool operator ==(Object other) =>
      other is InvalidKeyType && other.observedPrefix == observedPrefix;
  @override
  int get hashCode => observedPrefix.hashCode;
  @override
  String toString() =>
      'Invalid SDK key type: expected the mobile key prefix, got "$observedPrefix"';
}

/// Thrown when the SDK key is structurally malformed
final class MalformedSdkKey implements CoproductException {
  const MalformedSdkKey(this.reason);
  final String reason;
  @override
  bool operator ==(Object other) =>
      other is MalformedSdkKey && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
  @override
  String toString() => 'Malformed SDK key: $reason';
}

/// Thrown when a configuration value is invalid
final class InvalidConfig implements CoproductException {
  const InvalidConfig(this.field, this.reason);
  final String field;
  final String reason;
  @override
  bool operator ==(Object other) =>
      other is InvalidConfig && other.field == field && other.reason == reason;
  @override
  int get hashCode => Object.hash(field, reason);
  @override
  String toString() => 'Invalid config: field `$field` $reason';
}

/// Thrown when a cached snapshot uses a schema version this SDK does not support
final class UnsupportedSchemaVersion implements CoproductException {
  const UnsupportedSchemaVersion({required this.actual, required this.supported});
  final int actual;
  final int supported;
  @override
  bool operator ==(Object other) =>
      other is UnsupportedSchemaVersion &&
      other.actual == actual &&
      other.supported == supported;
  @override
  int get hashCode => Object.hash(actual, supported);
  @override
  String toString() =>
      'Unsupported schema version: snapshot is $actual, SDK supports $supported';
}

/// Thrown by a second initialize with a different SDK key or config while a
/// runtime already exists. Shut down first to reinitialize with new inputs
final class CoproductAlreadyInitialized implements CoproductException {
  const CoproductAlreadyInitialized();
  @override
  bool operator ==(Object other) => other is CoproductAlreadyInitialized;
  @override
  int get hashCode => (CoproductAlreadyInitialized).hashCode;
  @override
  String toString() =>
      'Coproduct is already initialized with different inputs; call shutdown first';
}

/// Thrown by an initialize that a shutdown cancelled before it completed
final class CoproductInitializationCancelled implements CoproductException {
  const CoproductInitializationCancelled();
  @override
  bool operator ==(Object other) => other is CoproductInitializationCancelled;
  @override
  int get hashCode => (CoproductInitializationCancelled).hashCode;
  @override
  String toString() => 'Initialization was cancelled by shutdown';
}

/// Translates a generated init error into its public type. Used by the wrapper
/// and unit tested here, so the production translation path is the tested one
CoproductException translateInitError(frb.InitError error) => switch (error) {
      frb.InitError_MissingSdkKey() => const MissingSdkKey(),
      frb.InitError_InvalidKeyType(:final prefix) => InvalidKeyType(prefix),
      frb.InitError_MalformedSdkKey(:final reason) => MalformedSdkKey(reason),
      frb.InitError_InvalidConfig(:final field, :final reason) =>
        InvalidConfig(field, reason),
      frb.InitError_UnsupportedSchemaVersion(:final actual, :final supported) =>
        UnsupportedSchemaVersion(actual: actual, supported: supported),
    };
