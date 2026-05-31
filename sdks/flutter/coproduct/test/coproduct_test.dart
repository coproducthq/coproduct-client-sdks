// Pure-Dart unit tests. The SDK surface itself needs the native library (covered
// by example/integration_test on a device); what is unit-testable here is the
// scaffold's host-capability mocks, whose call counting drives the demo's
// "Host callbacks" signal.

import 'package:coproduct/coproduct.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MockTransport counts requests and returns a stub 200', () async {
    final transport = MockTransport();
    expect(transport.completedHandshake, isFalse);

    final response = await transport.request(
      const HttpRequest(method: HttpMethod.get_, url: 'https://x', headers: []),
    );

    expect(transport.requestCount, 1);
    expect(transport.completedHandshake, isTrue);
    expect(response.status, 200);
  });

  test('MockSecureStore write-then-read completes the identity handshake',
      () async {
    final store = MockSecureStore();
    expect(store.completedHandshake, isFalse);

    await store.write('scaffold-handshake-id', 'ok');
    final value = await store.read('scaffold-handshake-id');

    expect(value, 'ok');
    expect(store.writeCount, 1);
    expect(store.readCount, 1);
    expect(store.completedHandshake, isTrue);
  });
}
