import 'dart:async';
import 'dart:convert';

import '../attribute_value.dart';
import '../client_backend.dart';
import '../errors.dart';
import '../provider_state.dart';

/// One stored flag value, tagged by the flag type the core would report.
///
/// The tag is what keeps a BOOL true distinguishable from a JSON true, so a
/// getter of the wrong type serves its caller default rather than the value.
///
/// These types are public within this library and exported from no barrel. They
/// are deliberately not underscore-private: the white-box tests import this
/// library directly and construct values no public setter can produce, such as a
/// non-finite number
sealed class StoredValue {
  const StoredValue();
}

final class StoredBool extends StoredValue {
  const StoredBool(this.value);
  final bool value;

  @override
  bool operator ==(Object other) => other is StoredBool && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class StoredString extends StoredValue {
  const StoredString(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is StoredString && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class StoredNumber extends StoredValue {
  const StoredNumber(this.value);
  final double value;

  // Two NaN values count as the same stored value, so a redelivered NaN does not
  // register as a change
  @override
  bool operator ==(Object other) =>
      other is StoredNumber &&
      (other.value == value || (other.value.isNaN && value.isNaN));

  @override
  int get hashCode => value.hashCode;
}

/// Holds both encodings on purpose. [json] is the text handed across the seam,
/// matching the generated surface. [decoded] is what equality compares, because
/// the core compares a parsed JSON value rather than serialized text, so two
/// maps with the same entries in a different insertion order are not a change
final class StoredJson extends StoredValue {
  StoredJson(this.json) : decoded = jsonDecode(json);

  final String json;
  final Object? decoded;

  @override
  bool operator ==(Object other) =>
      other is StoredJson && _jsonStorageEqual(other.decoded, decoded);

  // Structural equality without a matching hash, so a StoredJson is never a
  // valid map key. Nothing here uses one as such
  @override
  int get hashCode => 0;
}

/// Structural equality for a stored JSON value, matching what the core compares.
///
/// Deliberately not `jsonValuesEqual`, which treats an int and a double of the
/// same value as one value. That is the right rule for deciding whether a
/// delivered observation changed, but it is the wrong rule for storage: the core
/// compares a parsed JSON value, and its number type distinguishes an integer
/// from a float, so replacing 1 with 1.0 is a real change that must be stored and
/// delivered.
///
/// Key order does not matter, as in the core
bool _jsonStorageEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_jsonStorageEqual(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonStorageEqual(a[i], b[i])) return false;
    }
    return true;
  }
  // An int and a double are different JSON numbers, so compare the runtime type
  // before the value
  if (a is num && b is num) return a.runtimeType == b.runtimeType && a == b;
  return a == b;
}

/// A registered observation. Non-generic so registrations of different types
/// share one list while each keeps its own typed controller and projector
abstract interface class _Sink {
  String get key;
  bool get active;
  void deliver(StoredValue? value);
  void cancel();
}

final class _TypedSink<T> implements _Sink {
  _TypedSink(this.key, this._project);

  @override
  final String key;
  final T? Function(StoredValue?) _project;

  // Deliberately not sync: production delivery crosses the FFI onto Dart's event
  // loop, so a test pumps exactly as the real app needs a frame
  final StreamController<T?> controller = StreamController<T?>();
  bool _active = true;

  @override
  bool get active => _active;

  @override
  void deliver(StoredValue? value) {
    if (!_active) return;
    controller.add(_project(value));
  }

  /// Deactivates and closes, idempotently. Production cancellation closes the
  /// channel and completes the Dart stream, so a raw consumer waiting on done is
  /// released rather than left hanging
  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    unawaited(controller.close());
  }
}

/// An in-memory value source with no native library and no network, so a widget
/// test can exercise the reactive API on the Dart VM.
///
/// It reproduces the client contract, not the evaluation engine. Identity is
/// stored and never evaluated, and no targeting rules, segments, prerequisites,
/// rollouts, or bucketing exist here
final class InMemoryBackend implements CoproductClientBackend {
  InMemoryBackend({this.anonymousId = 'test-anonymous-id'})
      : _targetingKey = anonymousId;

  final String anonymousId;

  final Map<String, StoredValue> _flags = {};
  final List<_Sink> _sinks = [];

  ProviderState _state = ProviderState.ready;
  bool _shutdown = false;

  String _targetingKey;
  final Map<String, AttributeValue> _developerAttributes = {};
  String? _previousAnonymousId;

  static const _reservedNames = {'user_id', 'targetingKey'};

  bool get isShutDown => _shutdown;

  /// Live registration count. Exists so a white-box test can prove that
  /// cancellation and shutdown release their entries: without it, deleting the
  /// removal leaves a dead sink retained while every behavioral test stays
  /// green, because an inactive sink is already filtered out of delivery
  int get registrationCount => _sinks.length;

  String get targetingKey => _targetingKey;

  Map<String, AttributeValue> get developerAttributes =>
      Map<String, AttributeValue>.unmodifiable(_developerAttributes);

  /// Applies one mutation.
  ///
  /// Mirrors the core's transition fanout: snapshot the registrations, compare
  /// the stored tagged value, and deliver only on a real change. Typed
  /// projection happens after that decision, matching the core, where the
  /// adapter projects the delivered union per requested type. So a STRING flag
  /// moving from one value to another delivers null to a bool observation
  void set(String key, StoredValue? next) {
    if (_shutdown) {
      throw StateError('This harness has been shut down');
    }
    final previous = _flags[key];
    if (previous == next) return;

    final targets = _sinks.where((s) => s.key == key && s.active).toList();

    if (next == null) {
      _flags.remove(key);
    } else {
      _flags[key] = next;
    }

    for (final sink in targets) {
      sink.deliver(next);
    }
  }

  void setProviderState(ProviderState state) {
    if (_shutdown) {
      throw StateError('This harness has been shut down');
    }
    _state = state;
  }

  Future<void> shutdown() async {
    if (_shutdown) return;
    _shutdown = true;
    for (final sink in List<_Sink>.of(_sinks)) {
      sink.cancel();
    }
    _sinks.clear();
  }

  static bool? projectBool(StoredValue? v) => v is StoredBool ? v.value : null;

  static String? projectString(StoredValue? v) =>
      v is StoredString ? v.value : null;

  static double? projectNumber(StoredValue? v) =>
      v is StoredNumber ? v.value : null;

  static String? projectJson(StoredValue? v) => v is StoredJson ? v.json : null;

  /// Reproduces the native NUMBER to integer projection: truncate toward zero,
  /// accept the signed 64-bit lower bound, reject at or above 2^63, and reject a
  /// non-finite value as unavailable
  static int? projectInt(StoredValue? v) {
    if (v is! StoredNumber) return null;
    final value = v.value;
    if (!value.isFinite) return null;
    if (value >= 9223372036854775808.0 || value < -9223372036854775808.0) {
      return null;
    }
    return value.truncate();
  }

  @override
  bool getBool(String key, bool defaultValue) =>
      _shutdown ? defaultValue : projectBool(_flags[key]) ?? defaultValue;

  @override
  String getString(String key, String defaultValue) =>
      _shutdown ? defaultValue : projectString(_flags[key]) ?? defaultValue;

  @override
  int getInt(String key, int defaultValue) =>
      _shutdown ? defaultValue : projectInt(_flags[key]) ?? defaultValue;

  @override
  double getNumber(String key, double defaultValue) =>
      _shutdown ? defaultValue : projectNumber(_flags[key]) ?? defaultValue;

  @override
  String getJson(String key, String defaultValueJson) =>
      _shutdown ? defaultValueJson : projectJson(_flags[key]) ?? defaultValueJson;

  ObservationHandle<T> _observe<T>(
    String key,
    T? Function(StoredValue?) project,
  ) {
    if (_shutdown) {
      // Mirrors the core's pre-cancelled session: a null seed resolves to the
      // caller default, the stream is already closed, and nothing is retained
      final closed = StreamController<T?>()..close();
      return ObservationHandle<T>(
        seed: null,
        events: closed.stream,
        cancel: () {},
      );
    }
    final sink = _TypedSink<T>(key, project);
    _sinks.add(sink);
    return ObservationHandle<T>(
      seed: project(_flags[key]),
      events: sink.controller.stream,
      cancel: () {
        sink.cancel();
        _sinks.remove(sink);
      },
    );
  }

  @override
  ObservationHandle<bool> observeBool(String key) => _observe(key, projectBool);

  @override
  ObservationHandle<String> observeString(String key) =>
      _observe(key, projectString);

  @override
  ObservationHandle<int> observeInt(String key) => _observe(key, projectInt);

  @override
  ObservationHandle<double> observeNumber(String key) =>
      _observe(key, projectNumber);

  @override
  ObservationHandle<String> observeJson(String key) =>
      _observe(key, projectJson);

  Map<String, AttributeValue> _withoutReserved(
    Map<String, AttributeValue> attributes,
  ) =>
      Map<String, AttributeValue>.fromEntries(
        attributes.entries.where((e) => !_reservedNames.contains(e.key)),
      );

  @override
  Future<void> identify({
    required String userId,
    required Map<String, AttributeValue> attributes,
    required bool linkAnonymous,
  }) async {
    // Shutdown is checked before validation, matching the core, where the commit
    // is rejected on a shut-down client before the mutation closure that
    // validates the key ever runs. An empty key after shutdown is therefore a
    // silent success, not an error
    if (_shutdown) return;
    if (userId.isEmpty) {
      throw const InvalidTargetingKey();
    }
    // Captures the original anonymous id, not the current targeting key, so it
    // stays a stable link back to the pre-login session rather than tracking the
    // most recently identified user
    if (linkAnonymous) {
      _previousAnonymousId ??= anonymousId;
    } else {
      _previousAnonymousId = null;
    }
    _targetingKey = userId;
    _developerAttributes
      ..clear()
      ..addAll(_withoutReserved(attributes));
  }

  @override
  Future<void> setContext({
    required String targetingKey,
    required Map<String, AttributeValue> attributes,
  }) async {
    if (_shutdown) return;
    if (targetingKey.isEmpty) {
      throw const InvalidTargetingKey();
    }
    _targetingKey = targetingKey;
    _developerAttributes
      ..clear()
      ..addAll(_withoutReserved(attributes));
  }

  @override
  Future<void> updateAttributes(Map<String, AttributeValue> attributes) async {
    if (_shutdown) return;
    _developerAttributes.addAll(_withoutReserved(attributes));
  }

  @override
  Future<void> removeAttributes(List<String> names) async {
    if (_shutdown) return;
    for (final name in names) {
      _developerAttributes.remove(name);
    }
  }

  @override
  Future<void> signOut() async {
    if (_shutdown) return;
    _targetingKey = anonymousId;
    _previousAnonymousId = null;
    _developerAttributes.clear();
  }

  @override
  String? get previousAnonymousId => _previousAnonymousId;

  @override
  ProviderState get state => _state;
}
