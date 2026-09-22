import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/host_context_channel.dart';
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

  test('the diagnostic names the channel and the attribute, never a key', () {
    final message = const HostContextUnavailable().toString();
    expect(message, contains('app.coproduct.flutter/host_context'));
    expect(message, contains('device_type'));
    expect(message, isNot(contains('cpk_mob_')));
  });
}
