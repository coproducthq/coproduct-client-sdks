import { HttpOnboardingClient } from '../httpOnboardingClient';

function graphJson() {
  return {
    startScreenId: 'start',
    screens: [
      {
        id: 'start',
        html: '<p>hi</p>',
        transitions: [],
        defaultNext: { type: 'complete' },
      },
    ],
  };
}

function fakeResponse(ok: boolean, body: string) {
  return { ok, json: async () => JSON.parse(body) };
}

describe('HttpOnboardingClient', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it("GETs this environment's latest content URL and parses the graph", async () => {
    const mockFetch = jest
      .fn()
      .mockResolvedValue(fakeResponse(true, JSON.stringify(graphJson())));
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpOnboardingClient({ envSlug: 'production' });
    const graph = await client.fetchOnboardingFlow('flow-1');

    expect(mockFetch).toHaveBeenCalledWith(
      'https://content.coproduct.app/onboarding/flow-1/production/latest.json'
    );
    expect(graph?.startScreenId).toBe('start');
    expect(graph?.screens).toHaveLength(1);
  });

  it('scopes the URL to the configured environment', async () => {
    const mockFetch = jest
      .fn()
      .mockResolvedValue(fakeResponse(true, JSON.stringify(graphJson())));
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpOnboardingClient({ envSlug: 'staging' });
    await client.fetchOnboardingFlow('flow-1');

    expect(mockFetch).toHaveBeenCalledWith(
      'https://content.coproduct.app/onboarding/flow-1/staging/latest.json'
    );
  });

  it('returns undefined on a 404 -- not deployed to this environment yet', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        fakeResponse(false, 'not found')
      ) as unknown as typeof fetch;

    const client = new HttpOnboardingClient({ envSlug: 'production' });
    expect(await client.fetchOnboardingFlow('missing')).toBeUndefined();
  });

  it('returns undefined on a non-2xx, non-404 response', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        fakeResponse(false, 'server error')
      ) as unknown as typeof fetch;

    const client = new HttpOnboardingClient({ envSlug: 'production' });
    expect(await client.fetchOnboardingFlow('flow-1')).toBeUndefined();
  });

  it('returns undefined when the response body is not valid JSON', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        fakeResponse(true, 'not json')
      ) as unknown as typeof fetch;

    const client = new HttpOnboardingClient({ envSlug: 'production' });
    expect(await client.fetchOnboardingFlow('flow-1')).toBeUndefined();
  });

  it('returns undefined when the underlying request throws', async () => {
    global.fetch = jest
      .fn()
      .mockRejectedValue(
        new Error('connection failed')
      ) as unknown as typeof fetch;

    const client = new HttpOnboardingClient({ envSlug: 'production' });
    expect(await client.fetchOnboardingFlow('flow-1')).toBeUndefined();
  });
});
