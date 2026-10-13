import type { Entitlement } from './models/entitlement';
import type { PaywallSnapshot } from './models/paywallSnapshot';
import type {
  NativePaywallBridge,
  PurchaseResult,
} from './nativePaywallBridge';
import { parsePaywallAction } from './paywallAction';
import { PaywallServerError, type PaywallClient } from './paywallClient';

export type PaywallNavigationDecision = 'prevent' | 'navigate';

export type PaywallPurchaseErrorReason =
  | 'unresolvedProduct'
  | 'serverRejected'
  | 'networkError';

export interface PaywallPurchaseError {
  reason: PaywallPurchaseErrorReason;
  serverCode?: string;
}

export type SetPricesCallback = (
  pricesByPackageKey: Record<string, string>
) => Promise<void>;
// entitlements is the resolved set after this purchase/restore landed --
// empty for a cancelled/pending outcome, since nothing was recorded server-side
export type PurchaseResultCallback = (
  result: PurchaseResult,
  entitlements: Entitlement[]
) => void;
export type PurchaseErrorCallback = (error: PaywallPurchaseError) => void;

// Owns everything native does for one paywall session: resolving and
// injecting prices after load, and intercepting purchase/restore/dismiss
// taps. Deliberately does not construct or hold a WebView instance itself,
// so this logic stays unit-testable without a real WebView. Mirrors
// sdks/flutter/coproduct/lib/src/paywall/paywall_runtime.dart.
export class PaywallRuntime {
  private readonly bridge: NativePaywallBridge;
  private readonly client: PaywallClient;
  private readonly appUserId: string;
  private readonly platform: string;
  private readonly setPrices: SetPricesCallback;
  private readonly onPurchaseResult?: PurchaseResultCallback;
  private readonly onPurchaseError?: PurchaseErrorCallback;
  private readonly onDismiss?: () => void;
  private snapshot: PaywallSnapshot | undefined;

  constructor(args: {
    bridge: NativePaywallBridge;
    client: PaywallClient;
    appUserId: string;
    setPrices: SetPricesCallback;
    onPurchaseResult?: PurchaseResultCallback;
    onPurchaseError?: PurchaseErrorCallback;
    onDismiss?: () => void;
    platform?: string;
  }) {
    this.bridge = args.bridge;
    this.client = args.client;
    this.appUserId = args.appUserId;
    this.setPrices = args.setPrices;
    this.onPurchaseResult = args.onPurchaseResult;
    this.onPurchaseError = args.onPurchaseError;
    this.onDismiss = args.onDismiss;
    this.platform = args.platform ?? 'IOS';
  }

  // Resolves a localized price for every cta with a known product id, then
  // hands the whole map to setPrices in one call. A cta with no resolvable
  // product id, or whose priceFor call fails, is silently skipped -- the
  // server never renders a price for it either.
  async onSnapshotLoaded(snapshot: PaywallSnapshot): Promise<void> {
    this.snapshot = snapshot;
    const prices: Record<string, string> = {};
    for (const cta of snapshot.content.ctas) {
      const packageRef = snapshot.packages[cta.packageKey];
      const productId = packageRef?.iosProductId;
      if (productId == null) continue;
      try {
        prices[cta.packageKey] = await this.bridge.priceFor(
          productId,
          packageRef?.kind ?? 'subscription'
        );
      } catch {
        continue;
      }
    }
    if (Object.keys(prices).length > 0) await this.setPrices(prices);
  }

  async handleNavigationRequest(
    url: string
  ): Promise<PaywallNavigationDecision> {
    const action = parsePaywallAction(url);
    if (action == null) return 'navigate';

    switch (action.type) {
      case 'purchase':
        await this.handlePurchase(action.packageKey);
        break;
      case 'restore':
        await this.handleRestore();
        break;
      case 'dismiss':
        this.onDismiss?.();
        break;
    }
    return 'prevent';
  }

  private async handlePurchase(packageKey: string): Promise<void> {
    const packageRef = this.snapshot?.packages[packageKey];
    const productId = packageRef?.iosProductId;
    if (productId == null) {
      this.onPurchaseError?.({ reason: 'unresolvedProduct' });
      return;
    }

    const result = await this.bridge.purchase(
      productId,
      packageRef?.kind ?? 'subscription'
    );
    if (result.outcome !== 'success') {
      this.onPurchaseResult?.(result, []);
      return;
    }

    let entitlements: Entitlement[];
    try {
      entitlements = await this.client.recordPurchase({
        appUserId: this.appUserId,
        platform: this.platform,
        storeProductId: productId,
        storeTransactionId: result.transactionId ?? '',
        purchaseDate: result.purchaseDate ?? new Date(),
        expiresDate: result.expirationDate,
      });
    } catch (error) {
      if (error instanceof PaywallServerError) {
        this.onPurchaseError?.({
          reason: 'serverRejected',
          serverCode: error.code,
        });
      } else {
        // StoreKit already charged the user by this point (outcome ===
        // success, above) -- a transport failure reporting that purchase
        // must still surface a terminal callback, not propagate uncaught
        // and leave the paywall UI with no signal after a real charge
        this.onPurchaseError?.({ reason: 'networkError' });
      }
      return;
    }
    // Outside the try: a throwing onPurchaseResult callback must never be
    // misattributed as a networkError by the catch above
    this.onPurchaseResult?.(result, entitlements);
  }

  private async handleRestore(): Promise<void> {
    const transactions = await this.bridge.restore();
    if (transactions.length === 0) {
      // Nothing to restore is a legitimate, successful outcome -- distinct
      // from every found transaction failing to record, below
      this.onPurchaseResult?.({ outcome: 'success' }, []);
      return;
    }

    // recordPurchase recomputes and returns this appUserId's FULL
    // entitlement set from every active transaction on each call (not an
    // incremental diff), so the last successful call's result already
    // reflects every transaction recorded earlier in this loop -- no
    // merging across calls needed
    let entitlements: Entitlement[] = [];
    let anyRecorded = false;
    for (const tx of transactions) {
      try {
        entitlements = await this.client.recordPurchase({
          appUserId: this.appUserId,
          platform: this.platform,
          storeProductId: tx.productId,
          storeTransactionId: tx.transactionId,
          purchaseDate: tx.purchaseDate,
          expiresDate: tx.expirationDate,
        });
        anyRecorded = true;
      } catch {
        continue;
      }
    }
    if (!anyRecorded) {
      // Transactions existed but none recorded -- reporting success with
      // an empty entitlement list here would be indistinguishable from a
      // user who genuinely has nothing to restore, hiding a real prior
      // purchase whose restore never reached the server
      this.onPurchaseError?.({ reason: 'networkError' });
      return;
    }
    this.onPurchaseResult?.({ outcome: 'success' }, entitlements);
  }
}
