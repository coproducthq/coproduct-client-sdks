import type * as ReactNativeIap from 'react-native-iap';
import type { Purchase, PurchaseError, PurchaseIOS } from 'react-native-iap';
import type {
  NativePaywallBridge,
  PackageKind,
  PurchaseResult,
  RestoredTransaction,
} from './nativePaywallBridge';

/** What a paywall reports when the app has not installed react-native-iap */
export const MISSING_IAP_MESSAGE =
  'Paywalls need react-native-iap and react-native-nitro-modules, which the ' +
  'Coproduct SDK lists as optional peer dependencies. Install them with ' +
  '"npm install react-native-iap react-native-nitro-modules", then run ' +
  '"pod install" in ios/ and rebuild the app.';

// Loaded on first use rather than imported, so an app that never shows a
// paywall need not install react-native-iap, which also adds Google Play's
// billing permission to every Android app that links it. Metro treats a
// require inside try as an optional dependency, so a missing package reaches
// the catch below instead of failing the bundle
let iapModule: typeof ReactNativeIap | undefined;
function iap(): typeof ReactNativeIap {
  if (iapModule == null) {
    try {
      iapModule = require('react-native-iap') as typeof ReactNativeIap;
    } catch {
      throw new Error(MISSING_IAP_MESSAGE);
    }
  }
  return iapModule;
}

// react-native-iap's own request/fetch type: 'subs' for a subscription,
// 'in-app' for every one-time product (consumable or lifetime) -- there is
// no third store-side type for "lifetime", StoreKit2 only distinguishes
// subscription vs. one-time purchase.
function storeTypeFor(kind: PackageKind): 'subs' | 'in-app' {
  return kind === 'subscription' ? 'subs' : 'in-app';
}

// react-native-iap-backed NativePaywallBridge. Owns the one genuinely new
// piece of logic this port needs beyond a straight line-for-line Flutter
// port: react-native-iap's requestPurchase() is fire-and-forget -- its own
// resolved value is never the purchase outcome, confirmed against the
// library's own native spec doc comment
// (node_modules/react-native-iap/src/specs/RnIap.nitro.ts): "returns the
// dispatched purchase payload; the outcome arrives through the listeners."
// This class correlates one requestPurchase() call with whichever
// purchaseUpdatedListener/purchaseErrorListener event answers it, finishes
// the transaction as part of settling success (react-native-iap does not
// auto-finish by default), and resolves a single Promise<PurchaseResult> --
// restoring the simple awaited shape every other file in this feature (and
// Flutter) expects.
// Purchase = PurchaseAndroid | PurchaseIOS; expirationDateIOS only exists on
// the iOS variant. Safe to assume here because this bridge is iOS-only for
// this sub-project (see Global Constraints) -- requestPurchase above never
// requests an Android purchase, so every Purchase this bridge ever handles
// is a PurchaseIOS.
function expirationDateFor(purchase: Purchase): Date | undefined {
  const expirationDateIOS = (purchase as PurchaseIOS).expirationDateIOS;
  return expirationDateIOS != null ? new Date(expirationDateIOS) : undefined;
}

// react-native-iap requires initConnection() before any other call in this
// module (fetchProducts, requestPurchase, getAvailablePurchases all reject
// with a native "not prepared" error otherwise). The connection is a
// process-wide native resource meant to stay open for the app's lifetime
// (react-native-iap's own docs: "keeps the native connection open across
// screens"), so this is memoized once per JS runtime rather than
// opened/closed per paywall session.
let connectionReady: Promise<boolean> | undefined;
function ensureConnection(): Promise<boolean> {
  if (connectionReady == null) connectionReady = iap().initConnection();
  return connectionReady;
}

export class IapPaywallBridge implements NativePaywallBridge {
  // Loads react-native-iap when a paywall mounts, so a missing install fails
  // with an actionable message before any purchase is attempted
  constructor() {
    iap();
  }

  async priceFor(productId: string, kind: PackageKind): Promise<string> {
    await ensureConnection();
    const products =
      (await iap().fetchProducts({
        skus: [productId],
        type: storeTypeFor(kind),
      })) ?? [];
    const price = products[0]?.displayPrice;
    if (price == null)
      throw new Error(`No product found for id "${productId}"`);
    return price;
  }

  async purchase(
    productId: string,
    kind: PackageKind
  ): Promise<PurchaseResult> {
    const isConsumable = kind === 'consumable';
    // Listener registration below must stay synchronous with this call (no
    // await ahead of it): requestPurchase is fire-and-forget and its outcome
    // only ever arrives through these listeners, so if a caller's purchase
    // event could in principle fire before they're attached, it would be
    // missed. Connection readiness is therefore awaited further down, just
    // ahead of the native requestPurchase call, not here.
    return new Promise<PurchaseResult>((resolve, reject) => {
      const updatedSubscription = iap().purchaseUpdatedListener(
        (purchase: Purchase) => {
          if (purchase.productId !== productId) return;
          cleanup();
          // Deliberately not awaited: this listener callback itself isn't
          // awaited by its caller, so there's nothing to block on besides
          // the .finally() below, which resolves the outer Promise either way.
          // eslint-disable-next-line no-void
          void iap().finishTransaction({ purchase, isConsumable })
            .catch(() => {
              // Finishing an already-finished transaction, or a transient
              // native failure to finish, must not block reporting the
              // purchase itself -- the charge already happened
            })
            .finally(() => {
              resolve({
                outcome: 'success',
                transactionId: purchase.transactionId ?? undefined,
                productId: purchase.productId,
                purchaseDate: new Date(purchase.transactionDate),
                expirationDate: expirationDateFor(purchase),
              });
            });
        }
      );

      const errorSubscription = iap().purchaseErrorListener(
        (error: PurchaseError) => {
          if (error.productId != null && error.productId !== productId) return;
          cleanup();
          if (error.code === iap().ErrorCode.UserCancelled) {
            resolve({ outcome: 'cancelled' });
          } else if (error.code === iap().ErrorCode.Pending) {
            resolve({ outcome: 'pending' });
          } else {
            reject(new Error(error.message));
          }
        }
      );

      function cleanup(): void {
        updatedSubscription.remove();
        errorSubscription.remove();
      }

      ensureConnection()
        .then(() =>
          iap().requestPurchase({
            request: { apple: { sku: productId } },
            type: storeTypeFor(kind),
          })
        )
        .catch((error: unknown) => {
          cleanup();
          reject(error instanceof Error ? error : new Error(String(error)));
        });
    });
  }

  async restore(): Promise<RestoredTransaction[]> {
    await ensureConnection();
    const purchases = await iap().getAvailablePurchases();
    const restored: RestoredTransaction[] = [];
    for (const purchase of purchases) {
      try {
        await iap().finishTransaction({ purchase, isConsumable: false });
      } catch {
        // Already-finished or a transient native failure to finish must
        // not drop this transaction from the restored set
      }
      if (purchase.transactionId == null) continue;
      restored.push({
        transactionId: purchase.transactionId,
        productId: purchase.productId,
        purchaseDate: new Date(purchase.transactionDate),
        expirationDate: expirationDateFor(purchase),
      });
    }
    return restored;
  }
}
