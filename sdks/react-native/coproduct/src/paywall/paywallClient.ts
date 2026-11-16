import type { Entitlement } from './models/entitlement';
import type { PaywallSnapshot } from './models/paywallSnapshot';

// Thrown by any PaywallClient method whose HTTP response is not 2xx. Carries
// the server's own error code when the response body has one, so
// PaywallRuntime can distinguish e.g. unknown_product from an unrelated
// failure. Mirrors
// sdks/flutter/coproduct/lib/src/paywall/paywall_client.dart's
// PaywallServerError.
export class PaywallServerError extends Error {
  readonly statusCode: number;
  readonly code?: string;

  constructor(args: { statusCode: number; code?: string; message: string }) {
    super(args.message);
    this.name = 'PaywallServerError';
    this.statusCode = args.statusCode;
    this.code = args.code;
  }
}

// The HTTP contract CoproductPaywall/PaywallRuntime drive. An interface, not
// a concrete fetch wrapper, so PaywallRuntime stays unit-testable against a
// fake -- the same testability property onboarding's CoproductClient gives
// FlowRuntime.
export interface PaywallClient {
  // Fetches the paywall. Returns undefined when it isn't resolved for this
  // environment (404) -- the caller decides the fallback UI.
  fetchPaywall(paywallId: string): Promise<PaywallSnapshot | undefined>;

  // POST /v1/purchases. Throws PaywallServerError on a non-2xx response.
  recordPurchase(args: {
    appUserId: string;
    platform: string;
    storeProductId: string;
    storeTransactionId: string;
    purchaseDate: Date;
    expiresDate?: Date;
  }): Promise<Entitlement[]>;

  /**
   * POST /v1/purchases with the store's own proof of the purchase,
   * signed_transaction (iOS) or purchase_token (Android) when present, so the
   * server can check the purchase with Apple or Google instead of taking the
   * app's word. Throws PaywallServerError on a non-2xx response. Optional: a
   * client that implements only recordPurchase still works, the runtime falls
   * back to it and the server verifies what it can from the transaction id
   * alone.
   */
  recordPurchaseWithProof?(args: {
    appUserId: string;
    platform: string;
    storeProductId: string;
    storeTransactionId: string;
    purchaseDate: Date;
    expiresDate?: Date;
    signedTransaction?: string;
    purchaseToken?: string;
  }): Promise<Entitlement[]>;

  // GET /v1/entitlements. Throws PaywallServerError on a non-2xx response.
  getEntitlements(appUserId: string): Promise<Entitlement[]>;

  // POST /v1/identify. Throws PaywallServerError on a non-2xx response.
  identify(args: { appUserId: string; targetingKey: string }): Promise<void>;
}
