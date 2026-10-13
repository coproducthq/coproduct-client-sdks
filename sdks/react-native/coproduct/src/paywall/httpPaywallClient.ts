import { parseEntitlement, type Entitlement } from './models/entitlement';
import {
  parsePaywallSnapshot,
  type PaywallSnapshot,
} from './models/paywallSnapshot';
import { PaywallServerError, type PaywallClient } from './paywallClient';

type FetchResponse = {
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
};

// package:http-backed PaywallClient equivalent. Makes its own fetch calls
// rather than reusing the base SDK's internal transport, which has no
// public accessor for the sdk key or a request client. sdkKey is the same
// string the host app already passed to Coproduct.initialize(sdkKey).
// Mirrors sdks/flutter/coproduct/lib/src/paywall/http_paywall_client.dart.
export class HttpPaywallClient implements PaywallClient {
  private readonly sdkKey: string;
  private readonly envSlug?: string;
  private readonly edgeBaseUrl: string;
  private readonly apiBaseUrl: string;
  private readonly contentBaseUrl: string;

  constructor(args: {
    sdkKey: string;
    envSlug?: string;
    edgeBaseUrl?: string;
    apiBaseUrl?: string;
    contentBaseUrl?: string;
  }) {
    this.sdkKey = args.sdkKey;
    this.envSlug = args.envSlug;
    this.edgeBaseUrl = args.edgeBaseUrl ?? 'https://sdk.coproduct.app';
    this.apiBaseUrl = args.apiBaseUrl ?? 'https://api.coproduct.app';
    this.contentBaseUrl =
      args.contentBaseUrl ?? 'https://content.coproduct.app';
  }

  private get headers(): Record<string, string> {
    return {
      'Authorization': `Bearer ${this.sdkKey}`,
      'Content-Type': 'application/json',
    };
  }

  async fetchPaywall(paywallId: string): Promise<PaywallSnapshot | undefined> {
    return this.envSlug != null
      ? this.fetchPaywallFromContentCdn(paywallId, this.envSlug)
      : this.fetchPaywallFromApi(paywallId);
  }

  // GET {contentBaseUrl}/paywalls/{paywallId}/{envSlug}/latest.json. Returns
  // undefined on any failure, with no fallback to the api.
  private async fetchPaywallFromContentCdn(
    paywallId: string,
    envSlug: string
  ): Promise<PaywallSnapshot | undefined> {
    const url = `${this.contentBaseUrl}/paywalls/${paywallId}/${envSlug}/latest.json`;
    let response: FetchResponse;
    try {
      response = await fetch(url);
    } catch {
      return undefined;
    }
    if (!response.ok) return undefined;
    try {
      const json = await response.json();
      return parsePaywallSnapshot(json as Record<string, unknown>);
    } catch {
      return undefined;
    }
  }

  private async fetchPaywallFromApi(
    paywallId: string
  ): Promise<PaywallSnapshot | undefined> {
    const url = `${this.edgeBaseUrl}/v1/paywalls/${paywallId}`;
    const response = await fetch(url, { headers: this.headers });
    if (response.status === 404) return undefined;
    await this.throwIfError(response);
    const body = (await response.json()) as Record<string, unknown>;
    return parsePaywallSnapshot(body.paywall as Record<string, unknown>);
  }

  async recordPurchase(args: {
    appUserId: string;
    platform: string;
    storeProductId: string;
    storeTransactionId: string;
    purchaseDate: Date;
    expiresDate?: Date;
  }): Promise<Entitlement[]> {
    const url = `${this.apiBaseUrl}/v1/purchases`;
    const response = await fetch(url, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify({
        app_user_id: args.appUserId,
        platform: args.platform,
        store_product_id: args.storeProductId,
        transaction: {
          store_transaction_id: args.storeTransactionId,
          purchase_date: args.purchaseDate.toISOString(),
          ...(args.expiresDate
            ? { expires_date: args.expiresDate.toISOString() }
            : {}),
        },
      }),
    });
    await this.throwIfError(response);
    return this.entitlementsFromBody(await response.json());
  }

  async getEntitlements(appUserId: string): Promise<Entitlement[]> {
    const url = `${this.apiBaseUrl}/v1/entitlements?appUserId=${encodeURIComponent(appUserId)}`;
    const response = await fetch(url, { headers: this.headers });
    await this.throwIfError(response);
    return this.entitlementsFromBody(await response.json());
  }

  async identify(args: {
    appUserId: string;
    targetingKey: string;
  }): Promise<void> {
    const url = `${this.apiBaseUrl}/v1/identify`;
    const response = await fetch(url, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify({
        app_user_id: args.appUserId,
        targeting_key: args.targetingKey,
      }),
    });
    await this.throwIfError(response);
  }

  private entitlementsFromBody(body: unknown): Entitlement[] {
    const entitlements = (body as Record<string, unknown>)
      .entitlements as unknown[];
    return entitlements.map((e) =>
      parseEntitlement(e as Record<string, unknown>)
    );
  }

  private async throwIfError(response: FetchResponse): Promise<void> {
    if (response.ok) return;
    let code: string | undefined;
    let message = `Request failed with status ${response.status}`;
    try {
      const body = (await response.json()) as Record<string, unknown>;
      code = body.code as string | undefined;
      message = (body.error as string | undefined) ?? message;
    } catch {
      // Non-JSON error body -- keep the generic message
    }
    throw new PaywallServerError({
      statusCode: response.status,
      code,
      message,
    });
  }
}
