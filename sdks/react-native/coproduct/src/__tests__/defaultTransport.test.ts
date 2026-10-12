import { FetchTransport } from '../defaultTransport';
import { HttpMethod, TransportError } from '../generated/coproduct_ffi_uniffi';

describe('FetchTransport', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.useRealTimers();
  });

  it('translates an HttpRequest into a fetch call and back into an HttpResponse', async () => {
    const responseHeaders = new Map([['content-type', 'application/json']]);
    const mockFetch = jest.fn().mockResolvedValue({
      status: 200,
      headers: {
        forEach: (cb: (value: string, name: string) => void) =>
          responseHeaders.forEach((v, n) => cb(v, n)),
      },
      arrayBuffer: async () => new TextEncoder().encode('{"ok":true}').buffer,
    });
    global.fetch = mockFetch as unknown as typeof fetch;

    const transport = new FetchTransport();
    const response = await transport.request({
      method: HttpMethod.Post,
      url: 'https://sdk.coproduct.app/snapshot',
      headers: [{ name: 'authorization', value: 'Bearer abc' }],
      body: new TextEncoder().encode('{}').buffer,
    });

    expect(mockFetch).toHaveBeenCalledWith(
      'https://sdk.coproduct.app/snapshot',
      expect.objectContaining({
        method: 'POST',
        headers: { authorization: 'Bearer abc' },
      })
    );
    expect(response.status).toBe(200);
    expect(response.headers).toEqual([
      { name: 'content-type', value: 'application/json' },
    ]);
    expect(new TextDecoder().decode(response.body)).toBe('{"ok":true}');
  });

  it('sends a GET request with no body', async () => {
    const mockFetch = jest.fn().mockResolvedValue({
      status: 304,
      headers: { forEach: () => {} },
      arrayBuffer: async () => new ArrayBuffer(0),
    });
    global.fetch = mockFetch as unknown as typeof fetch;

    const transport = new FetchTransport();
    await transport.request({
      method: HttpMethod.Get,
      url: 'https://sdk.coproduct.app/snapshot',
      headers: [],
    });

    expect(mockFetch).toHaveBeenCalledWith(
      'https://sdk.coproduct.app/snapshot',
      expect.objectContaining({ method: 'GET', body: undefined })
    );
  });

  it('a 401/500 response is returned normally, not thrown — the core interprets the status', async () => {
    const mockFetch = jest.fn().mockResolvedValue({
      status: 401,
      headers: { forEach: () => {} },
      arrayBuffer: async () => new ArrayBuffer(0),
    });
    global.fetch = mockFetch as unknown as typeof fetch;

    const transport = new FetchTransport();
    const response = await transport.request({
      method: HttpMethod.Get,
      url: 'https://sdk.coproduct.app/x',
      headers: [],
    });

    expect(response.status).toBe(401);
  });

  it('maps an abort (timeout) to TransportError.Timeout', async () => {
    jest.useFakeTimers();
    const mockFetch = jest
      .fn()
      .mockImplementation((_url, init: RequestInit) => {
        return new Promise((_resolve, reject) => {
          init.signal?.addEventListener('abort', () => {
            const error = new Error('Aborted');
            error.name = 'AbortError';
            reject(error);
          });
        });
      });
    global.fetch = mockFetch as unknown as typeof fetch;

    const transport = new FetchTransport(1000);
    const requestPromise = transport.request({
      method: HttpMethod.Get,
      url: 'https://sdk.coproduct.app/x',
      headers: [],
    });
    let caught: unknown;
    const settled = requestPromise.catch((error) => {
      caught = error;
    });
    jest.advanceTimersByTime(1000);
    await settled;

    expect(TransportError.Timeout.instanceOf(caught)).toBe(true);
  });

  it('maps a generic fetch TypeError to TransportError.NetworkUnreachable', async () => {
    const mockFetch = jest
      .fn()
      .mockRejectedValue(new TypeError('Network request failed'));
    global.fetch = mockFetch as unknown as typeof fetch;

    const transport = new FetchTransport();
    try {
      await transport.request({
        method: HttpMethod.Get,
        url: 'https://sdk.coproduct.app/x',
        headers: [],
      });
      throw new Error('expected request() to throw');
    } catch (error) {
      expect(TransportError.NetworkUnreachable.instanceOf(error)).toBe(true);
    }
  });

  it('maps an unrecognized failure to TransportError.Other carrying the reason', async () => {
    const mockFetch = jest.fn().mockRejectedValue(new Error('something odd'));
    global.fetch = mockFetch as unknown as typeof fetch;

    const transport = new FetchTransport();
    try {
      await transport.request({
        method: HttpMethod.Get,
        url: 'https://sdk.coproduct.app/x',
        headers: [],
      });
      throw new Error('expected request() to throw');
    } catch (error) {
      expect(TransportError.Other.instanceOf(error)).toBe(true);
      expect(
        (error as InstanceType<typeof TransportError.Other>).inner.reason
      ).toContain('something odd');
    }
  });
});
