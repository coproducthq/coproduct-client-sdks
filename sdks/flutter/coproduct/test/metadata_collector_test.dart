import 'dart:async';

import 'package:coproduct/src/cancellation.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/metadata_collector.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, frb.FrbContextValue>> _collect(
  MetadataProviders p, {
  Duration deadline = const Duration(seconds: 1),
  Duration Function()? clock,
  CancellationSignal? cancel,
  MetadataObserver? observe,
}) =>
    collectStaticAttributes(p,
        deadline: deadline,
        clock: clock ?? () => Duration.zero,
        cancel: cancel ?? CancellationSignal(),
        observe: observe);

void main() {
  MetadataProviders providers({
    MetadataProvider? timezone,
    MetadataProvider? osVersion,
  }) =>
      MetadataProviders(
        platform: stringProvider(() async => 'android'),
        osVersion: osVersion ?? stringProvider(() async => '14'),
        appVersion: stringProvider(() async => '2.3.1'),
        appBuild: stringProvider(() async => '412'),
        locale: stringProvider(() async => 'en-US'),
        timezone: timezone ?? stringProvider(() async => 'America/New_York'),
      );

  test('collects every available attribute before the deadline', () {
    fakeAsync((async) {
      Map<String, frb.FrbContextValue>? attrs;
      _collect(providers(), clock: () => async.elapsed).then((r) => attrs = r);
      async.flushMicrotasks();
      expect(attrs!['platform'], const frb.FrbContextValue.string('android'));
      expect(attrs!['timezone'],
          const frb.FrbContextValue.string('America/New_York'));
    });
  });

  test('the returned map is unmodifiable', () {
    fakeAsync((async) {
      Map<String, frb.FrbContextValue>? attrs;
      _collect(providers(), clock: () => async.elapsed).then((r) => attrs = r);
      async.flushMicrotasks();
      expect(() => attrs!['x'] = const frb.FrbContextValue.string('y'),
          throwsUnsupportedError);
    });
  });

  test('a synchronously throwing provider omits only its field', () {
    fakeAsync((async) {
      Map<String, frb.FrbContextValue>? attrs;
      _collect(
        providers(osVersion: () => throw StateError('sync failure')),
        clock: () => async.elapsed,
      ).then((r) => attrs = r);
      async.flushMicrotasks();
      expect(attrs!.containsKey('os_version'), isFalse);
      expect(attrs!['platform'], const frb.FrbContextValue.string('android'));
    });
  });

  test('a value completing before the deadline is installed', () {
    fakeAsync((async) {
      Map<String, frb.FrbContextValue>? attrs;
      _collect(
        providers(
            osVersion: () =>
                Future.delayed(const Duration(milliseconds: 40),
                    () => const frb.FrbContextValue.string('14'))),
        deadline: const Duration(milliseconds: 50),
        clock: () => async.elapsed,
      ).then((r) => attrs = r);
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      expect(attrs!['os_version'], const frb.FrbContextValue.string('14'));
    });
  });

  test('a value completing at the exact deadline is installed', () {
    fakeAsync((async) {
      // The provider completion timer is registered before the deadline timer,
      // and fake_async drains microtasks between same-instant timers, so the
      // value records before the seal fires
      Map<String, frb.FrbContextValue>? attrs;
      _collect(
        providers(
            osVersion: () =>
                Future.delayed(const Duration(milliseconds: 50),
                    () => const frb.FrbContextValue.string('14'))),
        deadline: const Duration(milliseconds: 50),
        clock: () => async.elapsed,
      ).then((r) => attrs = r);
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      expect(attrs!['os_version'], const frb.FrbContextValue.string('14'));
    });
  });

  test('a provider still pending at the deadline is omitted, not awaited', () {
    fakeAsync((async) {
      final never = Completer<frb.FrbContextValue?>();
      Map<String, frb.FrbContextValue>? attrs;
      _collect(
        providers(osVersion: () => never.future),
        deadline: const Duration(milliseconds: 50),
        clock: () => async.elapsed,
      ).then((r) => attrs = r);
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      expect(attrs!.containsKey('os_version'), isFalse);
      expect(attrs!['platform'], const frb.FrbContextValue.string('android'));
    });
  });

  test('a value completing after the seal is rejected', () {
    fakeAsync((async) {
      final late = Completer<frb.FrbContextValue?>();
      Map<String, frb.FrbContextValue>? attrs;
      _collect(
        providers(osVersion: () => late.future),
        deadline: const Duration(milliseconds: 50),
        clock: () => async.elapsed,
      ).then((r) => attrs = r);
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      late.complete(const frb.FrbContextValue.string('14')); // arrives after the seal
      async.flushMicrotasks();
      expect(attrs!.containsKey('os_version'), isFalse);
    });
  });

  test('a provider erroring after the seal is swallowed', () {
    fakeAsync((async) {
      final late = Completer<frb.FrbContextValue?>();
      _collect(
        providers(osVersion: () => late.future),
        deadline: const Duration(milliseconds: 50),
        clock: () => async.elapsed,
      );
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      // If the terminal listener did not absorb this, fakeAsync surfaces an
      // uncaught error and fails the test
      late.completeError(StateError('late'));
      async.flushMicrotasks();
    });
  });

  test('cancellation throws rather than returning a partial result', () {
    fakeAsync((async) {
      final cancel = CancellationSignal()..cancel();
      Object? error;
      _collect(providers(), cancel: cancel, clock: () => async.elapsed)
          .then<void>((_) {}, onError: (Object e, StackTrace _) => error = e);
      async.flushMicrotasks();
      expect(error, isA<CoproductInitializationCancelled>());
    });
  });

  test('a cancel during sealing is caught by the final recheck', () {
    fakeAsync((async) {
      // elapse flushes the seal's microtasks, so an external post-elapse cancel
      // would be too late. Cancel synchronously from the observer as the wedged
      // field is reported at the seal, which lands after the seal and before the
      // collector's final synchronous recheck
      final cancel = CancellationSignal();
      Object? error;
      _collect(
        providers(osVersion: () => Completer<frb.FrbContextValue?>().future),
        deadline: const Duration(milliseconds: 50),
        clock: () => async.elapsed,
        cancel: cancel,
        observe: (field, elapsed, {required bool omitted}) {
          if (field == 'os_version' && omitted) cancel.cancel();
        },
      ).then<void>((_) {}, onError: (Object e, StackTrace _) => error = e);
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      expect(error, isA<CoproductInitializationCancelled>());
    });
  });

  test('no budget returns empty without invoking any provider', () {
    fakeAsync((async) {
      var invocations = 0;
      Future<frb.FrbContextValue?> counted() async {
        invocations++;
        return const frb.FrbContextValue.string('x');
      }

      Map<String, frb.FrbContextValue>? attrs;
      collectStaticAttributes(
        MetadataProviders(
          platform: counted,
          osVersion: counted,
          appVersion: counted,
          appBuild: counted,
          locale: counted,
          timezone: counted,
        ),
        deadline: Duration.zero,
        clock: () => async.elapsed,
        cancel: CancellationSignal(),
      ).then((r) => attrs = r);
      async.flushMicrotasks();
      expect(attrs, isEmpty);
      expect(invocations, 0);
    });
  });

  test('a provider may return a non-string attribute value', () async {
    final attributes = await _collect(
      providers(timezone: () async => const frb.FrbContextValue.number(7)),
    );
    expect(attributes['timezone'], const frb.FrbContextValue.number(7));
  });

  test('stringProvider omits an empty string', () async {
    final provider = stringProvider(() async => '');
    expect(await provider(), isNull);
  });

  test('stringProvider omits a null string', () async {
    final provider = stringProvider(() async => null);
    expect(await provider(), isNull);
  });

  test('stringProvider wraps a non-empty string', () async {
    final provider = stringProvider(() async => 'UTC');
    expect(await provider(), const frb.FrbContextValue.string('UTC'));
  });

  test('no budget still throws when the observer cancels during sealing', () {
    fakeAsync((async) {
      final cancel = CancellationSignal();
      Object? error;
      collectStaticAttributes(
        providers(),
        deadline: Duration.zero,
        clock: () => async.elapsed,
        cancel: cancel,
        observe: (field, elapsed, {required bool omitted}) => cancel.cancel(),
      ).then<void>((_) {}, onError: (Object e, StackTrace _) => error = e);
      async.flushMicrotasks();
      expect(error, isA<CoproductInitializationCancelled>());
    });
  });

  test('reports each field omission exactly once, including a wedged field', () {
    fakeAsync((async) {
      final counts = <String, int>{};
      final omissions = <String, bool>{};
      _collect(
        MetadataProviders(
          platform: stringProvider(() async => 'android'),
          osVersion: () => Completer<frb.FrbContextValue?>().future, // wedged
          appVersion: stringProvider(() async => ''),
          appBuild: stringProvider(() async => '42'),
          locale: stringProvider(() async => 'en-US'),
          timezone: stringProvider(() async => 'America/New_York'),
        ),
        deadline: const Duration(milliseconds: 50),
        clock: () => async.elapsed,
        observe: (field, elapsed, {required bool omitted}) {
          counts[field] = (counts[field] ?? 0) + 1;
          omissions[field] = omitted;
        },
      );
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      expect(counts, {
        'platform': 1,
        'os_version': 1,
        'app_version': 1,
        'app_build': 1,
        'locale': 1,
        'timezone': 1,
      });
      expect(omissions['platform'], isFalse);
      expect(omissions['os_version'], isTrue); // wedged, reported at the seal
      expect(omissions['app_version'], isTrue); // empty
      expect(omissions['app_build'], isFalse);
    });
  });

  test('a throwing observer never fails collection', () {
    fakeAsync((async) {
      Map<String, frb.FrbContextValue>? attrs;
      _collect(providers(),
              clock: () => async.elapsed,
              observe: (f, e, {required bool omitted}) =>
                  throw StateError('sink down'))
          .then((r) => attrs = r);
      async.flushMicrotasks();
      expect(attrs!['platform'], const frb.FrbContextValue.string('android'));
    });
  });
}
