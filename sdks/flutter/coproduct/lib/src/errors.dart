import 'rust/api.dart' as frb;

/// The shared marker for exceptions Coproduct throws. Catch a specific subtype
/// for a known condition, or this type to handle any Coproduct error.
///
/// Closed with `abstract final` rather than `sealed`: both prevent an outside
/// implementation, but `sealed` would additionally advertise an exhaustive
/// subtype set and let a consumer switch without a default, which would make
/// every future Coproduct exception type source-breaking. Every implementer
/// lives in this library, as Dart's library-scoped subtype rules require
abstract final class CoproductException implements Exception {}

/// Thrown when initialize is called from a spawned background isolate. The SDK
/// supports root isolates only: a background isolate can make request and
/// response plugin calls but cannot receive the unsolicited host messages the
/// live connectivity subscription needs. Each FlutterEngine has its own root
/// isolate, so multiple engines are supported
final class CoproductUnsupportedIsolate implements CoproductException {
  const CoproductUnsupportedIsolate();
  @override
  bool operator ==(Object other) => other is CoproductUnsupportedIsolate;
  @override
  int get hashCode => (CoproductUnsupportedIsolate).hashCode;
  @override
  String toString() =>
      'Coproduct.initialize must be called from a root isolate. '
      'Background isolates are not supported';
}

/// Handed to the developer's error reporter when the host-context plugin does
/// not answer. Distinct from a value the device declined to supply: this one
/// means the native side is unreachable, which leaves targeting on the
/// attributes it feeds silently falling through until it is fixed. Reported
/// once per initialization however many of its methods fail
final class HostContextUnavailable implements CoproductException {
  const HostContextUnavailable();
  @override
  bool operator ==(Object other) => other is HostContextUnavailable;
  @override
  int get hashCode => (HostContextUnavailable).hashCode;
  @override
  String toString() =>
      'Coproduct: the host-context plugin did not answer on channel '
      'app.coproduct.flutter/host_context. It supplies device_type, '
      'network_type, first_seen_at, and session_count, and whichever it could '
      'not answer for are absent. Either the plugin is not registered, or its '
      'native side is older than the Dart side and does not implement the '
      'method. Conditions '
      'that need those attributes to have a value will not match on this '
      'device';
}

/// Why the session attributes are unavailable. New causes may be added, so a
/// switch over this needs a default branch
final class SessionAttributesUnavailableCause {
  const SessionAttributesUnavailableCause._(this._name, this._description);

  /// The native session store could not be read reliably or did not confirm
  /// its write
  static const storageFailure = SessionAttributesUnavailableCause._(
      'storageFailure',
      'the native session store could not be read reliably or did not confirm '
          'its write, so this process omits the session attributes rather than '
          'publish values that may be wrong');

  /// The platform side answered with something that is not a valid session
  /// pair
  static const malformedResponse = SessionAttributesUnavailableCause._(
      'malformedResponse',
      'the host-context plugin answered beginSession with a malformed session '
          'record');

  final String _name;
  final String _description;

  @override
  String toString() => _name;
}

/// Handed to the developer's error reporter when first_seen_at and
/// session_count cannot be published for this run. The two are always omitted
/// together, never one without the other, and initialization proceeds.
/// [cause] distinguishes a storage failure from a malformed response. The text
/// of [toString] is for people to read and must not be parsed
final class SessionAttributesUnavailable implements CoproductException {
  const SessionAttributesUnavailable(this.cause);
  final SessionAttributesUnavailableCause cause;
  @override
  bool operator ==(Object other) =>
      other is SessionAttributesUnavailable && other.cause == cause;
  @override
  int get hashCode => cause.hashCode;
  @override
  String toString() =>
      'Coproduct: first_seen_at and session_count are not available for this '
      'run: ${cause._description}. Conditions that need them to have a value '
      'will not match in this process';
}

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

/// Thrown when the SDK key is not a Coproduct mobile SDK key, which starts with
/// `cpk_mob_`. It carries no part of the rejected key, because a value supplied
/// by mistake may be a secret that should never reach logs
final class InvalidKeyType implements CoproductException {
  const InvalidKeyType();
  @override
  bool operator ==(Object other) => other is InvalidKeyType;
  @override
  int get hashCode => (InvalidKeyType).hashCode;
  @override
  String toString() =>
      'Invalid SDK key type: expected a Coproduct mobile SDK key (cpk_mob_)';
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
      frb.InitError_InvalidKeyType() => const InvalidKeyType(),
      frb.InitError_MalformedSdkKey(:final reason) => MalformedSdkKey(reason),
      frb.InitError_InvalidConfig(:final field, :final reason) =>
        InvalidConfig(field, reason),
      frb.InitError_UnsupportedSchemaVersion(:final actual, :final supported) =>
        UnsupportedSchemaVersion(actual: actual, supported: supported),
    };

/// Thrown by `CoproductClient.identify` and `CoproductClient.setContext` when the
/// identity or targeting key is empty. The key is the identity of the evaluated
/// context, so an empty key is rejected rather than silently accepted
final class InvalidTargetingKey implements CoproductException {
  const InvalidTargetingKey();

  @override
  bool operator ==(Object other) => other is InvalidTargetingKey;

  @override
  int get hashCode => (InvalidTargetingKey).hashCode;

  @override
  String toString() => 'The identity or targeting key cannot be empty.';
}
