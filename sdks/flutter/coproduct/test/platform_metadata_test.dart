import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/metadata_collector.dart';
import 'package:coproduct/src/platform_metadata.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.coproduct.flutter/host_context');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Answers readHostInfo with whatever [answer] gives for each call, and
  /// counts the calls
  List<MethodCall> serve(Object? Function(int call) answer) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'readHostInfo') return null;
      calls.add(call);
      return answer(calls.length);
    });
    return calls;
  }

  /// Starts all three together, the way the collector runs them, and gives
  /// each one's value or error
  Future<List<Object?>> readAll(MetadataProviders providers) => Future.wait([
    for (final provider in [
      providers.osVersion,
      providers.appVersion,
      providers.appBuild,
    ])
      provider().then<Object?>((value) => value, onError: (Object e) => e),
  ]);

  test('each field reads its own value from the one answer', () async {
    serve(
      (_) => {
        'os_version': '18.2.1',
        'app_version': '2.4.0',
        'app_build': '20260101',
      },
    );
    expect(await readAll(platformMetadataProviders()), [
      const frb.FrbContextValue.string('18.2.1'),
      const frb.FrbContextValue.string('2.4.0'),
      const frb.FrbContextValue.string('20260101'),
    ]);
  });

  test('one channel call serves all three fields', () async {
    final calls = serve(
      (_) => {'os_version': '15', 'app_version': '1.0', 'app_build': '1'},
    );
    final providers = platformMetadataProviders();
    await readAll(providers);
    await readAll(providers);
    expect(calls, hasLength(1));
  });

  test('a failure resets the memo so a later read retries', () async {
    final calls = serve((call) {
      if (call == 1) throw PlatformException(code: 'boom');
      return {'os_version': '15', 'app_version': '1.0', 'app_build': '1'};
    });
    final providers = platformMetadataProviders();
    final failed = await readAll(providers);
    expect(failed, everyElement(isA<PlatformException>()));
    expect(await readAll(providers), [
      const frb.FrbContextValue.string('15'),
      const frb.FrbContextValue.string('1.0'),
      const frb.FrbContextValue.string('1'),
    ]);
    expect(calls, hasLength(2));
  });

  test('a missing plugin raises HostContextUnavailable from each field', () {
    // No handler installed, so the channel is genuinely missing
    final providers = platformMetadataProviders();
    expect(providers.osVersion(), throwsA(isA<HostContextUnavailable>()));
    expect(providers.appVersion(), throwsA(isA<HostContextUnavailable>()));
    expect(providers.appBuild(), throwsA(isA<HostContextUnavailable>()));
  });

  test('an empty or null value is omitted', () async {
    serve((_) => {'os_version': '', 'app_version': null, 'app_build': ''});
    expect(await readAll(platformMetadataProviders()), [null, null, null]);
  });

  test('a null answer omits every field', () async {
    serve((_) => null);
    expect(await readAll(platformMetadataProviders()), [null, null, null]);
  });
}
