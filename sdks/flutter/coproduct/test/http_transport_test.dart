import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:coproduct/src/http_transport.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A client that ignores the abort trigger and settles only when released, so a
/// test can hold the underlying send active after the caller-facing timeout has
/// fired and observe whether the transport closes it while it is still running
class _GatedClient extends http.BaseClient {
  bool sendActive = false;
  bool closedWhileActive = false;
  bool closed = false;
  final Completer<http.StreamedResponse> _gate =
      Completer<http.StreamedResponse>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete(http.StreamedResponse(Stream<List<int>>.empty(), 200));
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendActive = true;
    try {
      return await _gate.future;
    } finally {
      sendActive = false;
    }
  }

  @override
  void close() {
    if (sendActive) closedWhileActive = true;
    closed = true;
  }
}

void main() {
  test('maps a GET request and a 200 response across the boundary', () async {
    late http.Request captured;
    final transport = HttpTransport(
      requestTimeout: const Duration(seconds: 1),
      client: MockClient((req) async {
        captured = req;
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3]),
          200,
          headers: {'etag': 'abc'},
        );
      }),
    );
    final resp = await transport.request(frb.HttpRequest(
      method: frb.HttpMethod.get_,
      url: 'https://h/v1/snapshot',
      headers: const [frb.HttpHeader(name: 'authorization', value: 'Bearer k')],
      body: null,
    ));
    expect(captured.method, 'GET');
    expect(captured.url.toString(), 'https://h/v1/snapshot');
    expect(captured.headers['authorization'], 'Bearer k');
    expect(resp.status, 200);
    expect(resp.body, Uint8List.fromList([1, 2, 3]));
    expect(resp.headers.any((h) => h.name == 'etag' && h.value == 'abc'), isTrue);
    await transport.dispose();
  });

  test('maps a POST body', () async {
    late http.Request captured;
    final transport = HttpTransport(
      requestTimeout: const Duration(seconds: 1),
      client: MockClient((req) async {
        captured = req;
        return http.Response('', 204);
      }),
    );
    await transport.request(frb.HttpRequest(
      method: frb.HttpMethod.post,
      url: 'https://h/x',
      headers: const [],
      body: Uint8List.fromList([9, 9]),
    ));
    expect(captured.method, 'POST');
    expect(captured.bodyBytes, [9, 9]);
    await transport.dispose();
  });

  test('a request slower than the timeout throws (Future.timeout, not abort)',
      () async {
    // MockClient ignores the abort trigger and this send settles only when the
    // test releases it, so this proves the timeout bounds the request on its own,
    // the real socket abort is proven below
    final gate = Completer<http.Response>();
    final transport = HttpTransport(
      requestTimeout: const Duration(milliseconds: 20),
      client: MockClient((req) => gate.future),
    );
    await expectLater(
        transport.request(frb.HttpRequest(
          method: frb.HttpMethod.get_,
          url: 'https://h/x',
          headers: const [],
          body: null,
        )),
        throwsA(anything));
    // Release the underlying send so dispose does not wait on it
    gate.complete(http.Response('', 200));
    await transport.dispose();
  });

  test('a timed-out request aborts the underlying connection over a real socket',
      () async {
    // A raw socket server, not HttpServer: HttpServer pauses its request
    // subscription for the duration of a request and only resumes it once a
    // response is written, so a client disconnect while no response has been
    // written is never delivered to HttpRequest/HttpResponse. A bare
    // ServerSocket observes the connection directly, so it sees the abort
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    final received = Completer<void>();
    final terminated = Completer<void>();
    void markTerminated([Object? _]) {
      if (!terminated.isCompleted) terminated.complete();
    }

    server.listen((socket) {
      socket.listen(
        (data) {
          if (!received.isCompleted) received.complete();
          // The response is never written, so either settlement of done,
          // normal or error, means the client tore the connection down
        },
        onDone: markTerminated,
        onError: markTerminated,
      );
    });
    // The default client is used, so this exercises the real IOClient
    final transport =
        HttpTransport(requestTimeout: const Duration(milliseconds: 200));
    addTearDown(transport.dispose);

    await expectLater(
      transport.request(frb.HttpRequest(
        method: frb.HttpMethod.get_,
        url: 'http://${server.address.host}:${server.port}/hang',
        headers: const [],
        body: null,
      )),
      throwsA(isA<TimeoutException>()),
    );
    // The server first received the request, then the abort trigger fired on
    // timeout tears down the socket and the server observes the connection end
    await received.future.timeout(const Duration(seconds: 5));
    await terminated.future.timeout(const Duration(seconds: 5));
  });

  test('the reused client still serves a request after a timeout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      if (req.uri.path == '/ok') {
        req.response.statusCode = 200;
        req.response.write('ok');
        await req.response.close();
      }
      // /hang is never answered
    });
    final transport =
        HttpTransport(requestTimeout: const Duration(milliseconds: 200));
    addTearDown(transport.dispose);
    final base = 'http://${server.address.host}:${server.port}';

    // The first request times out and is aborted
    await expectLater(
      transport.request(frb.HttpRequest(
        method: frb.HttpMethod.get_,
        url: '$base/hang',
        headers: const [],
        body: null,
      )),
      throwsA(isA<TimeoutException>()),
    );

    // A second request on the same transport succeeds once the aborted send has
    // unwound, proving the abort did not tear down the reused client. The single
    // request guard rejects it until the prior send settles, so retry briefly
    frb.HttpResponse? resp;
    for (var attempt = 0; attempt < 100 && resp == null; attempt++) {
      try {
        resp = await transport.request(frb.HttpRequest(
          method: frb.HttpMethod.get_,
          url: '$base/ok',
          headers: const [],
          body: null,
        ));
      } on StateError {
        await Future<void>.delayed(Duration.zero);
      }
    }
    expect(resp, isNotNull);
    expect(resp!.status, 200);
    expect(utf8.decode(resp.body), 'ok');
  });

  test('dispose aborts an in-flight request then closes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    final received = Completer<void>();
    server.listen((socket) {
      socket.listen((_) {
        if (!received.isCompleted) received.complete();
      });
    });
    // A long timeout so only dispose can end the request within the test window
    final transport = HttpTransport(requestTimeout: const Duration(seconds: 30));
    final pending = transport.request(frb.HttpRequest(
      method: frb.HttpMethod.get_,
      url: 'http://${server.address.host}:${server.port}/hang',
      headers: const [],
      body: null,
    ));
    // Listen now so the aborted request's error is never unhandled
    final settled = expectLater(pending, throwsA(anything));
    await received.future.timeout(const Duration(seconds: 5));

    // Disposing while the request is in flight aborts it through the supported
    // trigger and completes without waiting out the deadline
    await transport.dispose().timeout(const Duration(seconds: 5));
    await settled;
  });

  test('dispose waits for the underlying send to settle before closing',
      () async {
    // The gated client ignores the abort trigger and settles only on release, so
    // the underlying send stays active after the caller-facing timeout fires
    final client = _GatedClient();
    final transport = HttpTransport(
      client: client,
      requestTimeout: const Duration(milliseconds: 20),
    );
    final pending = transport.request(frb.HttpRequest(
      method: frb.HttpMethod.get_,
      url: 'https://h/x',
      headers: const [],
      body: null,
    ));
    // Listen now so the timeout error is never unhandled
    final pendingSettled = expectLater(pending, throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(client.sendActive, isTrue); // the timeout fired but the send runs on

    var disposed = false;
    final disposing = transport.dispose().then((_) => disposed = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(disposed, isFalse); // dispose is waiting for the underlying send
    expect(client.closed, isFalse);

    client.release(); // the underlying send finally settles
    await disposing;
    expect(disposed, isTrue);
    expect(client.closed, isTrue);
    expect(client.closedWhileActive, isFalse); // close never raced an active send
    await pendingSettled;
  });

  test('a second request is rejected while the prior send is still unwinding',
      () async {
    // The gated client ignores the abort trigger, so after the first request's
    // caller-facing timeout its underlying send is still active
    final client = _GatedClient();
    final transport = HttpTransport(
      client: client,
      requestTimeout: const Duration(milliseconds: 20),
    );
    final first = transport.request(frb.HttpRequest(
      method: frb.HttpMethod.get_,
      url: 'https://h/a',
      headers: const [],
      body: null,
    ));
    final firstSettled = expectLater(first, throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(client.sendActive, isTrue); // the first send is still unwinding

    // A second request must be rejected because the first send has not settled,
    // so it cannot overwrite the shutdown bookkeeping the first send relies on
    await expectLater(
      transport.request(frb.HttpRequest(
        method: frb.HttpMethod.get_,
        url: 'https://h/b',
        headers: const [],
        body: null,
      )),
      throwsA(isA<StateError>()),
    );

    client.release(); // the first send settles
    await firstSettled;
    await transport.dispose();
  });
}
