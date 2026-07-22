import 'package:flutter/foundation.dart' show listEquals;

import 'rust/api.dart' as frb;

/// A targeting attribute value. One of the five cases the public context domain
/// supports: string, number, boolean, string list, or null
sealed class AttributeValue {
  const AttributeValue();

  const factory AttributeValue.string(String value) = StringAttributeValue;

  /// A numeric attribute. The value is stored as a double, so an integer
  /// identifier larger than 2^53 loses precision. Pass such an identifier as a
  /// string with [AttributeValue.string] instead
  factory AttributeValue.number(num value) =>
      NumberAttributeValue(value.toDouble());

  const factory AttributeValue.bool(bool value) = BoolAttributeValue;

  factory AttributeValue.stringList(Iterable<String> values) =>
      StringListAttributeValue(List<String>.unmodifiable(values));

  /// An explicit null attribute value. This is distinct from omitting the key,
  /// whose effect depends on the mutator, and from removing the key
  const factory AttributeValue.nullValue() = NullAttributeValue;
}

final class StringAttributeValue extends AttributeValue {
  const StringAttributeValue(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is StringAttributeValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class NumberAttributeValue extends AttributeValue {
  const NumberAttributeValue(this.value);
  final double value;

  @override
  bool operator ==(Object other) =>
      other is NumberAttributeValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class BoolAttributeValue extends AttributeValue {
  const BoolAttributeValue(this.value);
  final bool value;

  @override
  bool operator ==(Object other) =>
      other is BoolAttributeValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class StringListAttributeValue extends AttributeValue {
  const StringListAttributeValue(this.values);
  final List<String> values;

  @override
  bool operator ==(Object other) =>
      other is StringListAttributeValue && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

final class NullAttributeValue extends AttributeValue {
  const NullAttributeValue();

  @override
  bool operator ==(Object other) => other is NullAttributeValue;

  @override
  int get hashCode => (NullAttributeValue).hashCode;
}

/// Converts the public attribute value into the generated FFI representation.
/// Package-private so the generated type never reaches the public API
frb.FrbContextValue toFrbContextValue(AttributeValue value) => switch (value) {
      StringAttributeValue(:final value) => frb.FrbContextValue.string(value),
      NumberAttributeValue(:final value) => frb.FrbContextValue.number(value),
      BoolAttributeValue(:final value) => frb.FrbContextValue.bool(value),
      StringListAttributeValue(:final values) =>
        frb.FrbContextValue.stringList(values),
      NullAttributeValue() => frb.FrbContextValue.null_(),
    };

/// Snapshots and converts an attribute map into the FFI representation at call
/// time. Building a fresh map here, before the operation is queued, is what keeps
/// a later mutation of the caller's map from changing an already-queued operation
Map<String, frb.FrbContextValue> toFrbAttributes(
        Map<String, AttributeValue> attributes) =>
    attributes.map((key, value) => MapEntry(key, toFrbContextValue(value)));

/// Snapshots a key list into an unmodifiable copy at call time, so a later
/// mutation of the caller's list cannot change an already-queued removal
List<String> snapshotKeys(Iterable<String> keys) => List<String>.unmodifiable(keys);
