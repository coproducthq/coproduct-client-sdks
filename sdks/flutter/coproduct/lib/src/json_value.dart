import 'dart:collection';
import 'dart:convert';

/// Structural equality for decoded JSON values.
///
/// Maps compare by key set and value, so key order never registers as a
/// change. Numbers compare across `int` and `double`, so `1` and `1.0` are the
/// same value, and two NaN values are equal so a redelivered NaN does not
/// notify forever.
///
/// A value JSON cannot represent is equal only to itself. Comparing such a
/// value with `==` would let a type that defines its own equality make two
/// distinct caller defaults look like one, which would suppress a
/// re-registration that should have happened
bool jsonValuesEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      // containsKey rather than a null result, so a key holding null is not
      // confused with a key that is absent
      if (!b.containsKey(entry.key)) return false;
      if (!jsonValuesEqual(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonValuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  // The NaN clause states the rule outright. On this platform the identity
  // check above already answers it, because Dart compares doubles bitwise
  // there, so the clause changes no outcome and no test can pin it. It stays
  // because the rule should not depend on identity semantics for doubles
  if (a is num && b is num) return a == b || (a.isNaN && b.isNaN);
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  // Nothing else is a JSON value. Identity was already checked at the top, so
  // reaching here means two values that differ in type or that JSON cannot
  // represent, and a null against any non-null. None of those are equal
  return false;
}

/// Compares two caller-supplied JSON defaults the way an observation will
/// serve them.
///
/// Each side is normalized through JSON first, because that is what an
/// observation does with an encodable default. Two distinct objects that encode
/// to the same document are therefore the same default, and a widget holding
/// one does not tear down its native session to register an identical one. A
/// default JSON cannot encode falls back to the identity rule, which the
/// identity check at the top already applied
bool jsonDefaultsEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  final Object? left;
  final Object? right;
  try {
    left = jsonDecode(jsonEncode(a));
    right = jsonDecode(jsonEncode(b));
  } catch (_) {
    return false;
  }
  return jsonValuesEqual(left, right);
}

/// Wraps a decoded JSON value so a caller cannot mutate a structure the SDK
/// also holds. Maps and lists are wrapped recursively. Scalars are already
/// immutable.
///
/// Map keys are cast to `String` because every value reaching here either came
/// from `jsonDecode`, which produces string keys, or passed a `jsonEncode`
/// check, which rejects a map with non-string keys
Object? unmodifiableJson(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, Object?>({
      for (final entry in value.entries)
        entry.key as String: unmodifiableJson(entry.value),
    });
  }
  if (value is List) {
    return UnmodifiableListView<Object?>(
        [for (final element in value) unmodifiableJson(element)]);
  }
  return value;
}
