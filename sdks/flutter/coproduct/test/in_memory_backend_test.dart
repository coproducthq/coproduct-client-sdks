import 'package:coproduct/coproduct.dart';
import 'package:coproduct/src/testing/in_memory_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drains one asynchronous delivery turn
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late InMemoryBackend backend;

  setUp(() => backend = InMemoryBackend());

  group('reads', () {
    test('each typed getter serves its stored value', () {
      backend.set('b', const StoredBool(true));
      backend.set('s', const StoredString('x'));
      backend.set('n', const StoredNumber(1.5));
      backend.set('j', StoredJson('{"a":1}'));

      expect(backend.getBool('b', false), isTrue);
      expect(backend.getString('s', 'd'), 'x');
      expect(backend.getNumber('n', 0), 1.5);
      expect(backend.getJson('j', 'null'), '{"a":1}');
    });

    test('each typed getter serves the caller default when the flag is absent',
        () {
      expect(backend.getBool('missing', true), isTrue);
      expect(backend.getString('missing', 'd'), 'd');
      expect(backend.getInt('missing', 7), 7);
      expect(backend.getNumber('missing', 1.5), 1.5);
      expect(backend.getJson('missing', '"d"'), '"d"');
    });

    test('a wrong-type read serves the caller default', () {
      backend.set('k', const StoredBool(true));
      expect(backend.getString('k', 'default'), 'default');
      expect(backend.getNumber('k', 9), 9);
    });

    test('a JSON scalar is not readable by the matching scalar getter', () {
      backend.set('k', StoredJson('true'));
      expect(backend.getBool('k', false), isFalse);
    });

    test('a scalar is not readable by getJson', () {
      backend.set('k', const StoredBool(true));
      expect(backend.getJson('k', '"fallback"'), '"fallback"');
    });

    test('NUMBER serves both integer and number reads', () {
      backend.set('max-items', const StoredNumber(42.75));
      expect(backend.getInt('max-items', 0), 42);
      expect(backend.getNumber('max-items', 0), 42.75);
    });
  });

  group('delivery', () {
    test('each observation seeds synchronously from the latest stored value',
        () {
      backend.set('b', const StoredBool(true));
      backend.set('s', const StoredString('x'));
      backend.set('n', const StoredNumber(2.5));
      backend.set('j', StoredJson('[1]'));

      expect(backend.observeBool('b').seed, isTrue);
      expect(backend.observeString('s').seed, 'x');
      expect(backend.observeInt('n').seed, 2);
      expect(backend.observeNumber('n').seed, 2.5);
      expect(backend.observeJson('j').seed, '[1]');
    });

    test('a new observation does not receive an event enqueued before it '
        'registered', () async {
      backend.set('k', const StoredBool(true));
      final handle = backend.observeBool('k');
      final events = <bool?>[];
      handle.events.listen(events.add);

      await settle();
      expect(events, isEmpty);
      expect(handle.seed, isTrue);
    });

    test('an equal assignment enqueues no raw event', () async {
      backend.set('k', const StoredBool(true));
      final handle = backend.observeBool('k');
      final events = <bool?>[];
      handle.events.listen(events.add);

      backend.set('k', const StoredBool(true));
      await settle();

      expect(events, isEmpty);
    });

    test('a JSON assignment differing only in key order enqueues no raw event',
        () async {
      backend.set('config', StoredJson('{"a":1,"b":2}'));
      final handle = backend.observeJson('config');
      final events = <String?>[];
      handle.events.listen(events.add);

      backend.set('config', StoredJson('{"b":2,"a":1}'));
      await settle();

      expect(events, isEmpty);
    });

    test('replacing a JSON integer with a float is a change', () async {
      backend.set('k', StoredJson('1'));
      final handle = backend.observeJson('k');
      final events = <String?>[];
      handle.events.listen(events.add);

      backend.set('k', StoredJson('1.0'));
      await settle();

      // The core compares a parsed JSON value, whose number type distinguishes
      // an integer from a float, so this is a real change. jsonValuesEqual would
      // call them one value, which is the right rule for notifying an
      // observation and the wrong rule for storage
      expect(backend.getJson('k', 'null'), '1.0');
      expect(events, ['1.0']);
    });

    test('a JSON value differing only in key order is not a change', () async {
      backend.set('k', StoredJson('{"a":1,"b":2}'));
      final handle = backend.observeJson('k');
      final events = <String?>[];
      handle.events.listen(events.add);

      backend.set('k', StoredJson('{"b":2,"a":1}'));
      await settle();

      expect(events, isEmpty);
    });

    test('a STRING change delivers null to a bool observation', () async {
      backend.set('k', const StoredString('a'));
      final handle = backend.observeBool('k');
      final events = <bool?>[];
      handle.events.listen(events.add);

      backend.set('k', const StoredString('b'));
      await settle();

      // The stored tagged value changed, so the core would deliver. Typed
      // projection happens after that decision, so a bool observer sees null
      expect(events, [null]);
    });

    test('deliveries to one observation arrive in mutation order', () async {
      final handle = backend.observeInt('k');
      final events = <int?>[];
      handle.events.listen(events.add);

      backend.set('k', const StoredNumber(1));
      backend.set('k', const StoredNumber(2));
      backend.set('k', const StoredNumber(3));
      await settle();

      expect(events, [1, 2, 3]);
    });

    test('removal delivers null and each observation reverts to its own default',
        () async {
      backend.set('k', const StoredBool(true));
      final a = backend.observeBool('k');
      final b = backend.observeBool('k');
      final eventsA = <bool?>[];
      final eventsB = <bool?>[];
      a.events.listen(eventsA.add);
      b.events.listen(eventsB.add);

      backend.set('k', null);
      await settle();

      expect(eventsA, [null]);
      expect(eventsB, [null]);
      expect(backend.getBool('k', false), isFalse);
      expect(backend.getBool('k', true), isTrue);
    });

    test('an available JSON null is distinct from removal', () async {
      backend.set('k', StoredJson('null'));
      expect(backend.getJson('k', '"default"'), 'null');

      backend.set('k', null);
      expect(backend.getJson('k', '"default"'), '"default"');
    });

    test('disposing one observation does not affect another', () async {
      final a = backend.observeBool('k');
      final b = backend.observeBool('k');
      final eventsB = <bool?>[];
      b.events.listen(eventsB.add);

      a.cancel();
      backend.set('k', const StoredBool(true));
      await settle();

      expect(eventsB, [true]);
    });
  });

  group('cancellation and shutdown', () {
    test('cancellation enqueues no further event', () async {
      final handle = backend.observeBool('k');
      final events = <bool?>[];
      handle.events.listen(events.add);

      handle.cancel();
      backend.set('k', const StoredBool(true));
      await settle();

      expect(events, isEmpty);
    });

    test('cancellation completes the raw stream', () async {
      final handle = backend.observeBool('k');
      final done = expectLater(handle.events, emitsDone);
      handle.cancel();
      await done;
    });

    test('cancellation releases the registration', () {
      final handle = backend.observeBool('k');
      expect(backend.registrationCount, 1);
      handle.cancel();
      expect(backend.registrationCount, 0);
    });

    test('cancellation is idempotent', () async {
      final handle = backend.observeBool('k');
      handle.cancel();
      expect(handle.cancel, returnsNormally);
      expect(backend.registrationCount, 0);
    });

    test('shutdown closes every active raw stream', () async {
      final a = backend.observeBool('a');
      final b = backend.observeString('b');
      final doneA = expectLater(a.events, emitsDone);
      final doneB = expectLater(b.events, emitsDone);

      await backend.shutdown();
      await doneA;
      await doneB;
    });

    test('shutdown releases every registration', () async {
      backend.observeBool('a');
      backend.observeString('b');
      await backend.shutdown();
      expect(backend.registrationCount, 0);
    });

    test('shutdown is idempotent', () async {
      await backend.shutdown();
      await expectLater(backend.shutdown(), completes);
    });

    test('a setter after shutdown throws StateError', () async {
      await backend.shutdown();
      expect(() => backend.set('k', const StoredBool(true)), throwsStateError);
      expect(() => backend.setProviderState(ProviderState.stale),
          throwsStateError);
    });

    test('getters after shutdown serve the caller default', () async {
      backend.set('k', const StoredBool(true));
      await backend.shutdown();
      expect(backend.getBool('k', false), isFalse);
      expect(backend.getJson('k', '"d"'), '"d"');
    });

    test('registering after shutdown returns a null seed and a closed stream',
        () async {
      await backend.shutdown();
      final handle = backend.observeBool('k');

      expect(handle.seed, isNull);
      expect(backend.registrationCount, 0);
      await expectLater(handle.events, emitsDone);
      expect(handle.cancel, returnsNormally);
    });
  });

  group('integer projection, white box', () {
    test('a non-finite NUMBER projects to unavailable for getInt', () {
      backend.set('k', const StoredNumber(double.nan));
      expect(backend.getInt('k', 7), 7);
      expect(backend.getNumber('k', 7), isNaN);
    });

    test('an infinite NUMBER projects to unavailable for getInt', () {
      backend.set('k', const StoredNumber(double.infinity));
      expect(backend.getInt('k', 7), 7);
    });

    test('a NUMBER at or above 2^63 projects to unavailable', () {
      backend.set('k', const StoredNumber(9223372036854775808.0));
      expect(backend.getInt('k', 7), 7);
    });

    test('a NUMBER below the signed 64-bit lower bound projects to unavailable',
        () {
      backend.set('k', const StoredNumber(-9223372036854777856.0));
      expect(backend.getInt('k', 7), 7);
    });

    test('the lower bound itself is accepted', () {
      backend.set('k', const StoredNumber(-9223372036854775808.0));
      expect(backend.getInt('k', 7), -9223372036854775808);
    });

    test('truncation is toward zero', () {
      backend.set('k', const StoredNumber(-2.9));
      expect(backend.getInt('k', 0), -2);
    });
  });

  group('identity', () {
    test('identify replaces developer attributes', () async {
      await backend.updateAttributes({'a': const AttributeValue.string('1')});
      await backend.identify(
        userId: 'u1',
        attributes: {'b': const AttributeValue.string('2')},
        linkAnonymous: true,
      );
      expect(backend.developerAttributes.keys, ['b']);
      expect(backend.targetingKey, 'u1');
    });

    test('setContext replaces developer attributes', () async {
      await backend.updateAttributes({'a': const AttributeValue.string('1')});
      await backend.setContext(
        targetingKey: 't1',
        attributes: {'b': const AttributeValue.string('2')},
      );
      expect(backend.developerAttributes.keys, ['b']);
      expect(backend.targetingKey, 't1');
    });

    test('updateAttributes merges', () async {
      await backend.updateAttributes({'a': const AttributeValue.string('1')});
      await backend.updateAttributes({'b': const AttributeValue.string('2')});
      expect(backend.developerAttributes.keys, containsAll(['a', 'b']));
    });

    test('removeAttributes removes the named keys', () async {
      await backend.updateAttributes({
        'a': const AttributeValue.string('1'),
        'b': const AttributeValue.string('2'),
      });
      await backend.removeAttributes(['a']);
      expect(backend.developerAttributes.keys, ['b']);
    });

    test('reserved names are dropped from every identity mutator', () async {
      const reserved = {
        'user_id': AttributeValue.string('x'),
        'targetingKey': AttributeValue.string('y'),
        'plan': AttributeValue.string('pro'),
      };
      await backend.identify(
          userId: 'u1', attributes: reserved, linkAnonymous: true);
      expect(backend.developerAttributes.keys, ['plan']);

      await backend.updateAttributes(reserved);
      expect(backend.developerAttributes.keys, ['plan']);

      await backend.setContext(targetingKey: 't1', attributes: reserved);
      expect(backend.developerAttributes.keys, ['plan']);
    });

    test('a linked identify captures the original anonymous id once', () async {
      await backend.identify(
          userId: 'u1', attributes: {}, linkAnonymous: true);
      expect(backend.previousAnonymousId, backend.anonymousId);

      await backend.identify(
          userId: 'u2', attributes: {}, linkAnonymous: true);
      expect(backend.previousAnonymousId, backend.anonymousId);
    });

    test('an unlinked identify then a linked identify captures the original '
        'anonymous id', () async {
      await backend.identify(
          userId: 'u1', attributes: {}, linkAnonymous: false);
      await backend.identify(
          userId: 'u2', attributes: {}, linkAnonymous: true);

      expect(backend.previousAnonymousId, backend.anonymousId);
      expect(backend.previousAnonymousId, isNot('u1'));
    });

    test('an unlinked identify clears the captured id', () async {
      await backend.identify(
          userId: 'u1', attributes: {}, linkAnonymous: true);
      await backend.identify(
          userId: 'u2', attributes: {}, linkAnonymous: false);
      expect(backend.previousAnonymousId, isNull);
    });

    test('signOut restores the original anonymous id and clears attributes',
        () async {
      await backend.identify(
        userId: 'u1',
        attributes: {'plan': const AttributeValue.string('pro')},
        linkAnonymous: true,
      );
      await backend.signOut();

      expect(backend.targetingKey, backend.anonymousId);
      expect(backend.developerAttributes, isEmpty);
      expect(backend.previousAnonymousId, isNull);
    });

    test('an empty key before shutdown rejects', () async {
      await expectLater(
        backend.identify(userId: '', attributes: {}, linkAnonymous: true),
        throwsA(isA<InvalidTargetingKey>()),
      );
      await expectLater(
        backend.setContext(targetingKey: '', attributes: {}),
        throwsA(isA<InvalidTargetingKey>()),
      );
    });

    test('an empty key after shutdown succeeds rather than throwing', () async {
      // Discriminating: this is the only test that fails if validation runs
      // before the shutdown check. The valid-key test below passes either way
      await backend.shutdown();
      await expectLater(
        backend.identify(userId: '', attributes: {}, linkAnonymous: true),
        completes,
      );
      await expectLater(
        backend.setContext(targetingKey: '', attributes: {}),
        completes,
      );
    });

    test('identify after shutdown succeeds and changes nothing', () async {
      await backend.shutdown();
      await backend.identify(
          userId: 'u1', attributes: {}, linkAnonymous: true);
      expect(backend.targetingKey, backend.anonymousId);
    });

    test('updateAttributes after shutdown succeeds and changes nothing',
        () async {
      await backend.identify(
        userId: 'u1',
        attributes: {'plan': const AttributeValue.string('pro')},
        linkAnonymous: true,
      );
      await backend.shutdown();
      await backend.updateAttributes({'plan': const AttributeValue.string('free')});

      expect(backend.developerAttributes['plan'],
          const AttributeValue.string('pro'));
    });

    test('signOut after shutdown succeeds and changes nothing', () async {
      await backend.identify(
          userId: 'u1', attributes: {}, linkAnonymous: true);
      await backend.shutdown();
      await backend.signOut();

      expect(backend.targetingKey, 'u1');
    });

    test('no identity mutation changes any flag value', () async {
      backend.set('k', const StoredBool(true));
      await backend.identify(
          userId: 'u1', attributes: {}, linkAnonymous: true);
      await backend.updateAttributes({'a': const AttributeValue.string('1')});
      await backend.signOut();

      expect(backend.getBool('k', false), isTrue);
    });
  });

  group('provider state', () {
    test('a fresh backend reports ready', () {
      expect(backend.state, ProviderState.ready);
    });

    test('setProviderState is visible immediately, across all five values', () {
      expect(ProviderState.values, hasLength(5));
      for (final state in ProviderState.values) {
        backend.setProviderState(state);
        expect(backend.state, state);
      }
    });
  });
}
