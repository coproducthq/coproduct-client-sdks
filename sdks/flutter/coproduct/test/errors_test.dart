import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated InitError variants translate to public types', () {
    expect(translateInitError(const frb.InitError.missingSdkKey()),
        isA<MissingSdkKey>());
    expect(
        translateInitError(const frb.InitError.invalidKeyType(prefix: 'cpk_web_')),
        isA<InvalidKeyType>()
            .having((e) => e.observedPrefix, 'observedPrefix', 'cpk_web_'));
    expect(translateInitError(const frb.InitError.malformedSdkKey(reason: 'bad')),
        isA<MalformedSdkKey>());
    expect(
        translateInitError(
            const frb.InitError.invalidConfig(field: 'endpoint', reason: 'x')),
        isA<InvalidConfig>());
    expect(
        translateInitError(
            const frb.InitError.unsupportedSchemaVersion(actual: 9, supported: 1)),
        isA<UnsupportedSchemaVersion>());
  });

  test('every public error is a CoproductException, including identity', () {
    expect(const MissingSdkKey(), isA<CoproductException>());
    expect(const InvalidTargetingKey(), isA<CoproductException>());
  });

  test('field-bearing errors have value equality and hide the key', () {
    expect(const InvalidConfig('pollInterval', 'too small'),
        const InvalidConfig('pollInterval', 'too small'));
    expect(const InvalidKeyType('cpk_web_'), const InvalidKeyType('cpk_web_'));
    expect(const MissingSdkKey(), const MissingSdkKey());
    // Non-const instances to exercise the operator, not const canonicalization
    expect(InvalidTargetingKey(), InvalidTargetingKey());
    expect(const CoproductAlreadyInitialized().toString(), isNot(contains('cpk_')));
  });

  test('the session diagnostic names both attributes and never a key', () {
    for (final cause in [
      SessionAttributesUnavailableCause.storageFailure,
      SessionAttributesUnavailableCause.malformedResponse,
    ]) {
      final error = SessionAttributesUnavailable(cause);
      expect(error, isA<CoproductException>());
      expect(error.cause, same(cause));
      expect(error.toString(), contains('first_seen_at'));
      expect(error.toString(), contains('session_count'));
      expect(error.toString(), isNot(contains('cpk_')));
    }
  });

  test('the session diagnostic sentence carries the cause description', () {
    expect(
        SessionAttributesUnavailable(
                SessionAttributesUnavailableCause.storageFailure)
            .toString(),
        contains('native session store could not be read reliably'));
    expect(
        SessionAttributesUnavailable(
                SessionAttributesUnavailableCause.malformedResponse)
            .toString(),
        contains('malformed session record'));
  });

  test('session diagnostic equality and hashCode are keyed on the cause', () {
    // Non-const instances to exercise the operator, not const canonicalization
    const storage = SessionAttributesUnavailableCause.storageFailure;
    const malformed = SessionAttributesUnavailableCause.malformedResponse;
    expect(SessionAttributesUnavailable(storage),
        SessionAttributesUnavailable(storage));
    expect(SessionAttributesUnavailable(storage),
        isNot(SessionAttributesUnavailable(malformed)));
    expect(SessionAttributesUnavailable(storage).hashCode,
        SessionAttributesUnavailable(storage).hashCode);
    expect(SessionAttributesUnavailable(storage).hashCode,
        isNot(SessionAttributesUnavailable(malformed).hashCode));
  });

  test('a cause prints its name', () {
    expect(SessionAttributesUnavailableCause.storageFailure.toString(),
        'storageFailure');
    expect(SessionAttributesUnavailableCause.malformedResponse.toString(),
        'malformedResponse');
  });
}
