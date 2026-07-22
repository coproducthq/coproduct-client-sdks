import 'invalid_targeting_key.dart';
import 'rust/api.dart' as frb;

/// Runs an identity operation, translating only the generated invalid-key error
/// into the public [InvalidTargetingKey]. FRB surfaces the fieldless Rust error as
/// the thrown Dart enum value `IdentityError.invalidTargetingKey`. Every other
/// error propagates unchanged, preserving its type and stack trace, so an
/// unexpected failure stays distinguishable and is never remapped
Future<T> translateIdentityErrors<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on frb.IdentityError catch (error) {
    if (error == frb.IdentityError.invalidTargetingKey) {
      throw const InvalidTargetingKey();
    }
    rethrow;
  }
}
