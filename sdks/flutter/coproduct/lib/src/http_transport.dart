import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'rust/api.dart' as frb;

/// Default HTTP transport over package:http. Maps the FFI request and response
/// faithfully and bounds each request by [requestTimeout]. On timeout it aborts
/// the underlying request through package:http's supported abort trigger, which
/// tears down the socket so a timed-out request cannot outlive its poll, and it
/// surfaces a TimeoutException to the caller. It never retries, the core owns
/// retry, stale, rate-limit, and fatal behavior. The runtime polls serially, so
/// at most one request runs at a time, which request enforces. One client is
/// reused across polls. dispose aborts an in-flight request through the same
/// supported trigger and awaits the underlying send, not the timeout wrapper,
/// before closing the reused client, so the client is never closed while a
/// request is executing
class HttpTransport {
  HttpTransport({
    http.Client? client,
    required this.requestTimeout,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration requestTimeout;
  bool _disposed = false;
  bool _requestInFlight = false;
  Completer<void>? _activeAbort;
  Future<void>? _activeRequest;

  Future<frb.HttpResponse> request(frb.HttpRequest req) async {
    if (_disposed) {
      throw StateError('HttpTransport has been disposed');
    }
    if (_requestInFlight) {
      throw StateError('HttpTransport handles one request at a time');
    }
    // Build the request before marking in-flight, so a setup error such as an
    // unparseable url cannot strand the single-request guard
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      _methodName(req.method),
      Uri.parse(req.url),
      abortTrigger: abort.future,
    );
    for (final header in req.headers) {
      request.headers[header.name] = header.value;
    }
    final body = req.body;
    if (body != null) {
      request.bodyBytes = body;
    }
    // Track the settlement of the actual send, not the timeout wrapper, since
    // Future.timeout does not cancel its source. The in-flight guard and the
    // shutdown bookkeeping both release only when the send settles, so a new
    // request cannot start and dispose cannot close the client while a send is
    // still running, even for a client that ignores or is slow on the abort
    _requestInFlight = true;
    final source = _sendAndRead(request);
    final settled = source.then<void>((_) {}, onError: (_) {});
    _activeAbort = abort;
    _activeRequest = settled;
    unawaited(settled.whenComplete(() {
      _requestInFlight = false;
      if (identical(_activeAbort, abort)) _activeAbort = null;
      if (identical(_activeRequest, settled)) _activeRequest = null;
    }));
    try {
      // One deadline across send and body read. On timeout, fire the abort so
      // the socket is torn down, then surface a timeout to the caller. The
      // timeout also bounds a client that does not honor the abort trigger
      final response = await source.timeout(
        requestTimeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException(
              'Request exceeded $requestTimeout', requestTimeout);
        },
      );
      return frb.HttpResponse(
        status: response.statusCode,
        body: Uint8List.fromList(response.bodyBytes),
        headers: response.headers.entries
            .map((e) => frb.HttpHeader(name: e.key, value: e.value))
            .toList(),
      );
    } finally {
      // Fire the abort on every path so a client that honors it stops promptly,
      // completing it after the request has finished has no effect
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<http.Response> _sendAndRead(http.BaseRequest request) async {
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  /// Aborts an in-flight request through the supported trigger, waits for the
  /// underlying send to settle, then closes the reused client. Async so shutdown
  /// never closes the client while a request is executing
  Future<void> dispose() async {
    _disposed = true;
    final abort = _activeAbort;
    if (abort != null && !abort.isCompleted) {
      abort.complete();
    }
    final active = _activeRequest;
    if (active != null) {
      await active;
    }
    _client.close();
  }

  String _methodName(frb.HttpMethod method) => switch (method) {
        frb.HttpMethod.get_ => 'GET',
        frb.HttpMethod.post => 'POST',
      };
}
