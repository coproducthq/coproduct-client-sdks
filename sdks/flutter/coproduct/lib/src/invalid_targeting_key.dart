import 'errors.dart';

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
