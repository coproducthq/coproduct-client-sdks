import {
  parseOnboardingFlowGraph,
  type OnboardingFlowGraph,
} from './models/onboardingFlowGraph';

// Fetches an onboarding flow's graph directly from the R2-backed content
// CDN, bypassing the edge-worker round trip. An optional alternative
// content source for a CoproductClient adapter's fetchOnboardingFlow
// method -- a host's adapter can delegate to this class for that one
// method while still implementing flag resolution and sdk context itself,
// since this class knows nothing about either. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/http_onboarding_client.dart.
export class HttpOnboardingClient {
  private readonly envSlug: string;
  private readonly contentBaseUrl: string;

  constructor(args: { envSlug: string; contentBaseUrl?: string }) {
    this.envSlug = args.envSlug;
    this.contentBaseUrl =
      args.contentBaseUrl ?? 'https://content.coproduct.app';
  }

  // GET {contentBaseUrl}/onboarding/{flowId}/{envSlug}/latest.json. Returns
  // undefined on any failure -- not deployed to this environment yet
  // (404), a transport failure, or an unparseable body -- matching the
  // CoproductClient contract's documented fetchOnboardingFlow behavior
  // that a host adapter decides the fallback, not this class.
  async fetchOnboardingFlow(
    flowId: string
  ): Promise<OnboardingFlowGraph | undefined> {
    const url = `${this.contentBaseUrl}/onboarding/${flowId}/${this.envSlug}/latest.json`;
    let response: { ok: boolean; json: () => Promise<unknown> };
    try {
      response = await fetch(url);
    } catch {
      return undefined;
    }
    if (!response.ok) return undefined;
    try {
      const json = await response.json();
      return parseOnboardingFlowGraph(json as Record<string, unknown>);
    } catch {
      return undefined;
    }
  }
}
