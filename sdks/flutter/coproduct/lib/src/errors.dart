import 'rust/api.dart' as frb;

/// The type every exception the SDK throws implements.
///
/// Catch a specific subtype for a known condition, or this type to handle any
/// Coproduct exception. Flag reads never throw, and `Coproduct.initialize` and
/// the identity calls throw only for mistakes in your code, or when
/// `Coproduct.shutdown` interrupts `initialize`, never for network problems.
/// New subtypes may be added, so handle unknown ones
abstract final class CoproductException implements Exception {}

/// Thrown when `Coproduct.initialize` is called from a spawned background
/// isolate.
///
/// A spawned isolate cannot receive the platform messages the SDK relies on,
/// so call `initialize` from your app's main isolate. This is about Dart
/// isolates, not app lifecycle: an app running in the background is fine. Each
/// `FlutterEngine` has its own main isolate, so apps with several engines are
/// supported
final class CoproductUnsupportedIsolate implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
  const CoproductUnsupportedIsolate();
  @override
  bool operator ==(Object other) => other is CoproductUnsupportedIsolate;
  @override
  int get hashCode => (CoproductUnsupportedIsolate).hashCode;
  @override
  String toString() =>
      'Coproduct.initialize must be called from the app\'s main isolate, not '
      'from an isolate the app spawned. An app running in the background is '
      'unaffected';
}

/// Reported through `FlutterError.onError`, never thrown, when the SDK's
/// native plugin does not answer on `app.coproduct.flutter/host_context` or
/// `app.coproduct.flutter/network_type`. The report has `library` set to
/// `coproduct`.
///
/// Usually the plugin is not registered on the engine that ran
/// `Coproduct.initialize`, or its native side is older than the Dart side. A
/// hot restart does not rebuild the native side, so stop the app and rebuild
/// it after upgrading the SDK. A partial version skew can affect only some
/// attributes, so one or more of `device_type`, `network_type`,
/// `first_seen_at`, and `session_count` may then be absent or no longer
/// updating, and rules that need an absent attribute to have a value do not
/// match. Flags otherwise evaluate normally. Reported once per `initialize`,
/// in every build mode
final class HostContextUnavailable implements CoproductException {
  /// Creates the report. The SDK creates it, so you construct one only to
  /// compare against, for example in a test
  const HostContextUnavailable();
  @override
  bool operator ==(Object other) => other is HostContextUnavailable;
  @override
  int get hashCode => (HostContextUnavailable).hashCode;
  @override
  String toString() =>
      'Coproduct: the SDK\'s native plugin did not answer on channel '
      'app.coproduct.flutter/host_context or app.coproduct.flutter/network_type. '
      'One or more of device_type, network_type, first_seen_at, and '
      'session_count may be absent or no longer updating. Either the plugin '
      'is not registered, or its native side is older than the Dart side and '
      'does not implement the method. Conditions that need an absent '
      'attribute to have a value will not match on this device';
}

/// Why [SessionAttributesUnavailable] was reported.
///
/// More causes may be added, so a `switch` over this needs a default branch
final class SessionAttributesUnavailableCause {
  const SessionAttributesUnavailableCause._(this._name, this._description);

  /// The device's storage failed, or could not be trusted, for example on a
  /// launch before the device's first unlock after a restart. That case needs
  /// no action. On Android the underlying exception is in logcat under the tag
  /// `Coproduct`
  static const storageFailure = SessionAttributesUnavailableCause._(
      'storageFailure',
      'the device storage that holds the SDK\'s launch record could not be '
          'read reliably or did not confirm a save, so the SDK leaves these '
          'attributes unset rather than risk wrong values');

  /// The SDK's native plugin returned a launch record the SDK could not read
  static const malformedResponse = SessionAttributesUnavailableCause._(
      'malformedResponse',
      'the SDK\'s native plugin returned a launch record the SDK could not '
          'read');

  final String _name;
  final String _description;

  @override
  String toString() => _name;
}

/// Reported through `FlutterError.onError`, never thrown, when the SDK could
/// not read or save its launch record. The report has `library` set to
/// `coproduct`.
///
/// The automatic attributes `first_seen_at` and `session_count` are then both
/// unset until the next launch, so rules that need them to have a value do not
/// match. The SDK otherwise starts normally. [cause] says what went wrong.
/// The text of [toString] is for people to read, not for parsing
final class SessionAttributesUnavailable implements CoproductException {
  /// Creates the report. The SDK creates it, so you construct one only to
  /// compare against, for example in a test
  const SessionAttributesUnavailable(this.cause);

  /// What went wrong: a storage failure or an unreadable launch record
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

/// Thrown by `Coproduct.initialize` when the SDK key is empty. Pass your
/// mobile SDK key
final class MissingSdkKey implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
  const MissingSdkKey();
  @override
  bool operator ==(Object other) => other is MissingSdkKey;
  @override
  int get hashCode => (MissingSdkKey).hashCode;
  @override
  String toString() => 'A Coproduct SDK key is required';
}

/// Thrown by `Coproduct.initialize` when the SDK key does not start with
/// `cpk_mob_`, such as a server key.
///
/// This SDK accepts only mobile keys, so issue a mobile key for your project.
/// The exception carries no part of the key you passed, because a value
/// supplied by mistake may be a secret that should never reach logs
final class InvalidKeyType implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
  const InvalidKeyType();
  @override
  bool operator ==(Object other) => other is InvalidKeyType;
  @override
  int get hashCode => (InvalidKeyType).hashCode;
  @override
  String toString() =>
      'Invalid SDK key type: expected a Coproduct mobile SDK key (cpk_mob_)';
}

/// Thrown by `Coproduct.initialize` when the SDK key starts with `cpk_mob_`
/// but has the wrong length or characters.
///
/// A mobile key is `cpk_mob_` followed by 32 lowercase Crockford base32
/// characters: digits and letters other than `i`, `l`, `o`, and `u`, as
/// issued by Coproduct. The placeholder `cpk_mob_...` throws this, so a key
/// you forgot to replace fails straight away. A well-formed key that Coproduct
/// rejects, such as a revoked one, does not throw
final class MalformedSdkKey implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
  const MalformedSdkKey(this.reason);

  /// What is wrong with the key, for people to read
  final String reason;
  @override
  bool operator ==(Object other) =>
      other is MalformedSdkKey && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
  @override
  String toString() => 'Malformed SDK key: $reason';
}

/// Thrown by `Coproduct.initialize` when a `CoproductConfig` value is invalid.
/// The SDK never silently corrects a value
final class InvalidConfig implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
  const InvalidConfig(this.field, this.reason);

  /// The name of the `CoproductConfig` field, such as `pollInterval`
  final String field;

  /// Why the value is invalid, such as `must be at least 30 seconds`
  final String reason;
  @override
  bool operator ==(Object other) =>
      other is InvalidConfig && other.field == field && other.reason == reason;
  @override
  int get hashCode => Object.hash(field, reason);
  @override
  String toString() => 'Invalid config: field `$field` $reason';
}

/// Reserved for a future release. This version of the SDK never throws it.
///
/// Saved flags in a format this version does not understand are ignored, and
/// the launch behaves like a first launch. Downloaded flags in such a format
/// are ignored, and the SDK keeps serving the flags it had
final class UnsupportedSchemaVersion implements CoproductException {
  /// Creates the exception. The SDK never throws it
  const UnsupportedSchemaVersion({required this.actual, required this.supported});

  /// The format version of the flags the SDK received
  final int actual;

  /// The format version this SDK understands
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

/// Thrown by `Coproduct.initialize` when the SDK is already running with a
/// different key or config.
///
/// Calling `initialize` again with the same key and config returns the same
/// client instead. To change either, call `Coproduct.shutdown` first
final class CoproductAlreadyInitialized implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
  const CoproductAlreadyInitialized();
  @override
  bool operator ==(Object other) => other is CoproductAlreadyInitialized;
  @override
  int get hashCode => (CoproductAlreadyInitialized).hashCode;
  @override
  String toString() =>
      'Coproduct.initialize was called again with a different SDK key or '
      'config. Call Coproduct.shutdown() first to change them';
}

/// Thrown by `Coproduct.initialize` when `Coproduct.shutdown` ran before it
/// finished.
///
/// Expected if your app shuts down during startup. Catch it and stop
final class CoproductInitializationCancelled implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
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

/// Thrown by `CoproductClient.identify` and `CoproductClient.setContext` when
/// the user id or targeting key is empty. Pass a non-empty stable id
final class InvalidTargetingKey implements CoproductException {
  /// Creates the exception. The SDK throws it, so you construct one only to
  /// compare against, for example in a test
  const InvalidTargetingKey();

  @override
  bool operator ==(Object other) => other is InvalidTargetingKey;

  @override
  int get hashCode => (InvalidTargetingKey).hashCode;

  @override
  String toString() => 'The identity or targeting key cannot be empty.';
}
