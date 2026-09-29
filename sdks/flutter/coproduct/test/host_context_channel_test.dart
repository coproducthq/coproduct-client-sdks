import 'dart:async';

import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/host_context_channel.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:coproduct/src/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.coproduct.flutter/host_context');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns the platform value', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readDeviceType');
      return 'tablet';
    });
    expect(await const HostContextChannel().readDeviceType(), 'tablet');
  });

  test('a null platform answer is an omission, not a failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await const HostContextChannel().readDeviceType(), isNull);
  });

  test('an unregistered plugin raises HostContextUnavailable', () async {
    // No mock handler installed, so the channel is genuinely missing
    expect(() => const HostContextChannel().readDeviceType(),
        throwsA(isA<HostContextUnavailable>()));
  });

  test('the diagnostic names the channel and every attribute it feeds', () {
    final message = const HostContextUnavailable().toString();
    expect(message, contains('app.coproduct.flutter/host_context'));
    expect(message, contains('app.coproduct.flutter/network_type'));
    expect(message, contains('device_type'));
    expect(message, contains('network_type'));
    expect(message, contains('first_seen_at'));
    expect(message, contains('session_count'));
    // Both causes, because an unregistered plugin and a native side that lacks
    // the method raise the same exception
    expect(message, contains('not registered'));
    expect(message, contains('older'));
    expect(message, isNot(contains('cpk_mob_')));
  });

  group('beginSession', () {
    Future<Object?> answer(Object? raw) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'beginSession');
        return raw;
      });
      try {
        return await const HostContextChannel().beginSession();
      } catch (error) {
        return error;
      }
    }

    test('a whole pair is returned as one value', () async {
      expect(await answer({'first_seen_at': 1767225600, 'session_count': 3}),
          const SessionPair(firstSeenAt: 1767225600, sessionCount: 3));
    });

    test('the smallest valid values are accepted, which a first launch needs',
        () async {
      expect(await answer({'first_seen_at': 0, 'session_count': 1}),
          const SessionPair(firstSeenAt: 0, sessionCount: 1));
    });

    test('pairs differing in either value are not equal', () {
      const pair = SessionPair(firstSeenAt: 1, sessionCount: 2);
      expect(pair, isNot(const SessionPair(firstSeenAt: 1, sessionCount: 3)));
      expect(pair, isNot(const SessionPair(firstSeenAt: 2, sessionCount: 2)));
      expect(SessionPair(firstSeenAt: 1, sessionCount: 2).hashCode,
          SessionPair(firstSeenAt: 1, sessionCount: 2).hashCode);
      expect(SessionPair(firstSeenAt: 1, sessionCount: 2).hashCode,
          isNot(SessionPair(firstSeenAt: 1, sessionCount: 3).hashCode));
    });

    test('the largest exact integers are accepted and publish unchanged',
        () async {
      final pair = await answer(
          {'first_seen_at': kMaxExactInteger, 'session_count': kMaxExactInteger});
      expect(pair,
          const SessionPair(
              firstSeenAt: kMaxExactInteger, sessionCount: kMaxExactInteger));
      expect((pair! as SessionPair).attributes['session_count'],
          const frb.FrbContextValue.number(9007199254740991));
    });

    test('a null answer is a storage failure', () async {
      expect(await answer(null),
          const SessionAttributesUnavailable(
              SessionAttributesUnavailableCause.storageFailure));
    });

    test('a native exception is a storage failure too', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'error', message: 'disk full');
      });
      await expectLater(const HostContextChannel().beginSession(),
          throwsA(const SessionAttributesUnavailable(
              SessionAttributesUnavailableCause.storageFailure)));
    });

    test('anything short of a whole valid pair is rejected whole', () async {
      final malformed = <Object?>[
        {'first_seen_at': 1767225600},
        {'session_count': 3},
        {'first_seen_at': 1767225600, 'session_count': 3.0},
        {'first_seen_at': '1767225600', 'session_count': 3},
        {'first_seen_at': -1, 'session_count': 3},
        {'first_seen_at': 1767225600, 'session_count': 0},
        {'first_seen_at': kMaxExactInteger + 1, 'session_count': 3},
        {'first_seen_at': 1767225600, 'session_count': kMaxExactInteger + 1},
        [1767225600, 3],
        'session',
      ];
      for (final raw in malformed) {
        expect(await answer(raw),
            const SessionAttributesUnavailable(
                SessionAttributesUnavailableCause.malformedResponse),
            reason: '$raw');
      }
    });

    test('an unregistered plugin raises HostContextUnavailable', () async {
      expect(() => const HostContextChannel().beginSession(),
          throwsA(isA<HostContextUnavailable>()));
    });

    test('the pair reaches the core as numbers, not strings', () {
      // The acceptance rows cannot see this: the core's numeric operators also
      // parse numeric strings, so only this pins the representation
      expect(
          const SessionPair(firstSeenAt: 1767225600, sessionCount: 3).attributes,
          {
            'first_seen_at': const frb.FrbContextValue.number(1767225600),
            'session_count': const frb.FrbContextValue.number(3),
          });
    });
  });

  group('network_type events', () {
    const networkChannel = EventChannel('app.coproduct.flutter/network_type');

    tearDown(() => messenger.setMockStreamHandler(networkChannel, null));

    test('each listen carries its epoch and receives the envelope', () async {
      Object? listenedWith;
      messenger.setMockStreamHandler(
        networkChannel,
        MockStreamHandler.inline(onListen: (arguments, events) {
          listenedWith = arguments;
          events.success({'epoch': arguments, 'value': 'wifi'});
        }),
      );
      final first =
          await const HostContextChannel().networkTypeEvents(12).first;
      expect(listenedWith, 12);
      expect(first, {'epoch': 12, 'value': 'wifi'});
    });

    test('a listen replacing a cancelled one keeps its handler and the calls '
        'reach the native side in order', () async {
      final calls = <String>[];
      messenger.setMockStreamHandler(
        networkChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            calls.add('listen $arguments');
            events.success({'epoch': arguments, 'value': 'wifi'});
          },
          onCancel: (arguments) => calls.add('cancel $arguments'),
        ),
      );
      final seen = <Object?>[];
      final first =
          const HostContextChannel().networkTypeEvents(1).listen(seen.add);
      await pumpEventQueue();
      // Cancelled and replaced in one synchronous step, as a resume does
      unawaited(first.cancel());
      final second =
          const HostContextChannel().networkTypeEvents(2).listen(seen.add);
      await pumpEventQueue();
      expect(calls, ['listen 1', 'cancel 1', 'listen 2']);
      expect(seen, [
        {'epoch': 1, 'value': 'wifi'},
        {'epoch': 2, 'value': 'wifi'},
      ]);
      await second.cancel();
      await pumpEventQueue();
      expect(calls.last, 'cancel 2');
    });

    test('a native error arrives as a stream error', () async {
      messenger.setMockStreamHandler(
        networkChannel,
        MockStreamHandler.inline(onListen: (arguments, events) {
          events.error(code: 'registration-failed', message: 'too many');
        }),
      );
      await expectLater(
        const HostContextChannel().networkTypeEvents(1),
        emitsError(isA<PlatformException>()
            .having((e) => e.code, 'code', 'registration-failed')),
      );
    });

    test('a native side without the network channel errors the stream once '
        'with HostContextUnavailable and reports nothing through FlutterError',
        () async {
      // An older native side registers the method channel but not this one.
      // The failure arrives on the stream, where the caller reports it once,
      // and neither the listen nor the cancel reports through FlutterError
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final seen = <Object>[];
      final subscription = const HostContextChannel()
          .networkTypeEvents(1)
          .listen((_) => seen.add('event'),
              onError: (Object error) => seen.add(error),
              onDone: () => seen.add('done'));
      await pumpEventQueue();
      await subscription.cancel();
      await pumpEventQueue();
      expect(seen, [const HostContextUnavailable()]);
      expect(reported, isEmpty);
    });

    test('a native listen that replies with an error arrives as a stream error',
        () async {
      const methods = MethodChannel('app.coproduct.flutter/network_type');
      addTearDown(() => messenger.setMockMethodCallHandler(methods, null));
      messenger.setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'listen') throw PlatformException(code: 'boom');
        return null;
      });
      await expectLater(
        const HostContextChannel().networkTypeEvents(1),
        emitsError(isA<PlatformException>().having((e) => e.code, 'code', 'boom')),
      );
    });
  });
}
