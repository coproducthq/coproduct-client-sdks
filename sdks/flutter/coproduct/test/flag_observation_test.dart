import 'dart:async';

import 'package:coproduct/src/flag_observation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('seeding', () {
    test('seeds from the session seed', () {
      final events = StreamController<bool?>();
      addTearDown(events.close);
      final observation = boolObservation(
        defaultValue: false,
        seed: true,
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      expect(observation.value, isTrue);
    });

    test('an unavailable seed resolves to the caller default', () {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = stringObservation(
        defaultValue: 'fallback',
        seed: null,
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      expect(observation.value, 'fallback');
    });
  });

  group('delivery', () {
    test('applies a delivered value and notifies once', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = stringObservation(
        defaultValue: 'default',
        seed: 'first',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      var notifications = 0;
      observation.addListener(() => notifications += 1);

      events.add('second');
      await pumpEventQueue();

      expect(observation.value, 'second');
      expect(notifications, 1);
    });

    test('an unchanged redelivery does not notify', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = stringObservation(
        defaultValue: 'default',
        seed: 'same',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      var notifications = 0;
      observation.addListener(() => notifications += 1);

      events..add('same')..add('same');
      await pumpEventQueue();

      expect(observation.value, 'same');
      expect(notifications, 0,
          reason: 'a value equal to the current one is not a change');
    });

    test('an unavailable delivery resolves to the caller default', () async {
      final events = StreamController<bool?>();
      addTearDown(events.close);
      final observation = boolObservation(
        defaultValue: true,
        seed: false,
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      events.add(null);
      await pumpEventQueue();

      expect(observation.value, isTrue,
          reason: 'a flag that left the snapshot serves the caller default');
    });

    test('delivers integer values', () async {
      final events = StreamController<int?>();
      addTearDown(events.close);
      final observation = intObservation(
        defaultValue: -1,
        seed: null,
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      expect(observation.value, -1);

      events.add(42);
      await pumpEventQueue();

      expect(observation.value, 42);
    });

    test('treats a redelivered NaN as unchanged but a change away as a change',
        () async {
      final events = StreamController<double?>();
      addTearDown(events.close);
      final observation = numberObservation(
        defaultValue: 0.0,
        seed: double.nan,
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      var notifications = 0;
      observation.addListener(() => notifications += 1);

      events.add(double.nan);
      await pumpEventQueue();
      expect(notifications, 0, reason: 'NaN did not become a different value');

      events.add(1.5);
      await pumpEventQueue();
      expect(notifications, 1);
      expect(observation.value, 1.5);
    });

    test('reports a stream error instead of letting it escape', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      final observation = stringObservation(
        defaultValue: 'default',
        seed: 'held',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      events.addError(StateError('the native stream failed'));
      await pumpEventQueue();

      expect(reported, hasLength(1),
          reason: 'an unhandled stream error would escape into the zone');
      expect(reported.single.exception, isA<StateError>());
      expect(observation.value, 'held',
          reason: 'an error is not a value, so the last one stands');
    });

    test('retains the last value when the stream completes', () async {
      final events = StreamController<String?>();
      final observation = stringObservation(
        defaultValue: 'default',
        seed: 'held',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      await events.close();
      await pumpEventQueue();

      expect(observation.value, 'held',
          reason: 'shutdown freezes the observation rather than resetting it');
    });
  });

  group('json', () {
    test('decodes and exposes an unmodifiable value', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = jsonObservation(
        defaultValue: const {'caller': 'default'},
        seed: '{"a":[1]}',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      final seeded = observation.value! as Map<String, Object?>;
      expect(seeded['a'], [1]);
      expect(() => seeded['b'] = 1, throwsUnsupportedError);
    });

    test('does not notify when only key order changes', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = jsonObservation(
        defaultValue: null,
        seed: '{"one":1,"two":2}',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      var notifications = 0;
      observation.addListener(() => notifications += 1);

      events.add('{"two":2,"one":1}');
      await pumpEventQueue();
      expect(notifications, 0,
          reason: 'key order is not a value change');

      events.add('{"one":1,"two":3}');
      await pumpEventQueue();
      expect(notifications, 1);
    });

    test('an unavailable delivery resolves to an unmodifiable default',
        () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = jsonObservation(
        defaultValue: {'caller': 'default'},
        seed: '{"a":1}',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      events.add(null);
      await pumpEventQueue();

      final value = observation.value! as Map<String, Object?>;
      expect(value['caller'], 'default');
      expect(() => value['caller'] = 'mutated', throwsUnsupportedError);
    });

    test('a malformed payload resolves to the default', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = jsonObservation(
        defaultValue: const {'caller': 'default'},
        seed: 'not json at all',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      expect((observation.value! as Map)['caller'], 'default');

      events.add('{"a":1}');
      await pumpEventQueue();
      expect((observation.value! as Map)['a'], 1);

      events.add('{ broken');
      await pumpEventQueue();
      expect((observation.value! as Map)['caller'], 'default');
    });

    test('distinguishes a JSON null payload from an unavailable delivery',
        () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = jsonObservation(
        defaultValue: const {'caller': 'default'},
        seed: '{"a":1}',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      // 'null' is a valid JSON document whose value is null, which is a real
      // flag value. A raw null is the absence of any value
      events.add('null');
      await pumpEventQueue();
      expect(observation.value, isNull);

      events.add(null);
      await pumpEventQueue();
      expect((observation.value! as Map)['caller'], 'default');
    });

    test('delivers scalar payloads', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = jsonObservation(
        defaultValue: 'unset',
        seed: '42',
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);
      expect(observation.value, 42);

      events.add('"text"');
      await pumpEventQueue();
      expect(observation.value, 'text');

      events.add('true');
      await pumpEventQueue();
      expect(observation.value, isTrue);
    });

    test('serves a decoded immutable form of a default with a toJson method',
        () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final observation = jsonObservation(
        defaultValue: _Encodable(),
        seed: null,
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      // getJson round-trips such a default through JSON and returns the decoded
      // form, so an unavailable observation must serve the same thing
      final value = observation.value! as Map<String, Object?>;
      expect(value['kind'], 'custom');
      expect(() => value['kind'] = 'mutated', throwsUnsupportedError);
    });

    test('retains an unencodable default by identity', () async {
      final events = StreamController<String?>();
      addTearDown(events.close);
      final unencodable = _Opaque();
      final observation = jsonObservation(
        defaultValue: unencodable,
        seed: null,
        events: events.stream,
        cancel: () {},
      );
      addTearDown(observation.dispose);

      expect(identical(observation.value, unencodable), isTrue,
          reason: 'a default JSON cannot encode is kept exactly as supplied');

      var notifications = 0;
      observation.addListener(() => notifications += 1);
      events.add(null);
      await pumpEventQueue();
      expect(notifications, 0,
          reason: 'the same retained default is not a change');
    });
  });

  group('disposal', () {
    test('cancels the native subscription once and is idempotent', () {
      final events = StreamController<bool?>();
      addTearDown(events.close);
      var cancels = 0;
      final observation = boolObservation(
        defaultValue: false,
        seed: false,
        events: events.stream,
        cancel: () => cancels += 1,
      );

      observation.dispose();
      observation.dispose();

      expect(cancels, 1);
    });

    test('stops listening to the native stream', () async {
      final events = StreamController<bool?>();
      addTearDown(events.close);
      final observation = boolObservation(
        defaultValue: false,
        seed: false,
        events: events.stream,
        cancel: () {},
      );

      observation.dispose();
      await pumpEventQueue();

      expect(events.hasListener, isFalse);
    });

    test('drops a delivery that arrives after disposal', () async {
      // An ordinary stream stops delivering the moment its subscription is
      // cancelled, so it can never reach the disposed observation at all. This
      // one keeps delivering after cancel, which is the only way to put a
      // delivery and a disposal in the order the latch exists to survive
      final events = StreamController<bool?>();
      addTearDown(events.close);
      final observation = boolObservation(
        defaultValue: false,
        seed: false,
        events: _KeepsDelivering<bool?>(events.stream),
        cancel: () {},
      );
      var notifications = 0;
      observation.addListener(() => notifications += 1);

      observation.dispose();
      events.add(true);
      await pumpEventQueue();

      expect(notifications, 0,
          reason: 'a disposed observation notifies nobody');
      expect(observation.value, isFalse,
          reason: 'and it keeps the value it was disposed holding');
    });

    test('completes disposal and reports when the native cancel throws', () {
      final events = StreamController<bool?>();
      addTearDown(events.close);
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      var cancels = 0;
      final observation = boolObservation(
        defaultValue: false,
        seed: false,
        events: events.stream,
        cancel: () {
          cancels += 1;
          throw StateError('native session already gone');
        },
      );

      // Disposal runs from framework teardown, so it must not throw
      expect(observation.dispose, returnsNormally);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());

      // The notifier was still torn down, which addListener proves by
      // asserting against a disposed ChangeNotifier
      expect(() => observation.addListener(() {}), throwsAssertionError);

      // And a second disposal stays inert rather than throwing again
      expect(observation.dispose, returnsNormally);
      expect(cancels, 1);
      expect(reported, hasLength(1));
    });
  });
}

/// Delivers to its listener even after the subscription is cancelled. Real
/// streams detach on cancel, so this is the only way a test can drive the
/// post-disposal path that the disposed latch guards
class _KeepsDelivering<T> extends Stream<T> {
  _KeepsDelivering(this._source);

  final Stream<T> _source;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // The real subscription is deliberately kept and never cancelled, so events
    // continue to arrive after the caller cancels the one it is handed
    _source.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    return _InertSubscription<T>();
  }
}

class _InertSubscription<T> implements StreamSubscription<T> {
  @override
  Future<void> cancel() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Opaque {}

class _Encodable {
  Map<String, Object?> toJson() => {'kind': 'custom'};
}
