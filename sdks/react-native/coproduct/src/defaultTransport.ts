import {
  HttpMethod,
  TransportError,
  type HostTransport,
  type HttpHeader,
  type HttpRequest,
  type HttpResponse,
} from './generated/coproduct_ffi_uniffi';

// Production HostTransport default, using React Native's global fetch.
// MockTransport (src/index.tsx) stays available for tests but is no longer
// the implicit default. Mirrors URLSessionTransport.swift: connection-level
// failures (timeout, no connectivity, anything unclassified) throw a typed
// TransportError; a successful-but-4xx/5xx response is still returned
// normally, since the core interprets the status code, not the transport.
export class FetchTransport implements HostTransport {
  constructor(private readonly requestTimeoutMs?: number) {}

  async request(req: HttpRequest): Promise<HttpResponse> {
    const headers: Record<string, string> = {};
    for (const header of req.headers) {
      headers[header.name] = header.value;
    }

    const controller = new AbortController();
    const timeoutId =
      this.requestTimeoutMs !== undefined
        ? setTimeout(() => controller.abort(), this.requestTimeoutMs)
        : undefined;

    let response: Response;
    try {
      response = await fetch(req.url, {
        method: methodToString(req.method),
        headers,
        body: req.body,
        signal: controller.signal,
      });
    } catch (error) {
      throw classifyFetchError(error);
    } finally {
      if (timeoutId !== undefined) clearTimeout(timeoutId);
    }

    const body = await response.arrayBuffer();
    const responseHeaders: HttpHeader[] = [];
    response.headers.forEach((value, name) => {
      responseHeaders.push({ name, value });
    });

    return {
      status: response.status,
      body,
      headers: responseHeaders,
    };
  }
}

// RN's fetch polyfill has no granular error-code taxonomy like iOS's
// URLError: an aborted request (our own timeout) surfaces as an AbortError,
// and everything else connection-level collapses to a generic TypeError
// ("Network request failed"). Anything neither of those is truly
// unclassified and carries its message through as TransportError.Other,
// matching URLSessionTransport.swift's catch-all case.
function classifyFetchError(error: unknown): Error {
  if (error instanceof Error && error.name === 'AbortError') {
    return TransportError.Timeout.new();
  }
  if (error instanceof TypeError) {
    return TransportError.NetworkUnreachable.new();
  }
  return TransportError.Other.new({ reason: String(error) });
}

function methodToString(method: HttpMethod): string {
  switch (method) {
    case HttpMethod.Get:
      return 'GET';
    case HttpMethod.Post:
      return 'POST';
  }
}
