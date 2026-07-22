/// Thrown by `CoproductClient.identify` and `CoproductClient.setContext` when the
/// identity or targeting key is empty. The key is the identity of the evaluated
/// context, so an empty key is rejected rather than silently accepted
final class InvalidTargetingKey implements Exception {
  const InvalidTargetingKey();

  @override
  String toString() => 'The identity or targeting key cannot be empty.';
}
