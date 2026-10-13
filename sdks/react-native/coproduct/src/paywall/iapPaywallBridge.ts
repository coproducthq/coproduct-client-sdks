import {
  ErrorCode,
  fetchProducts,
  finishTransaction,
  getAvailablePurchases,
  purchaseErrorListener,
  purchaseUpdatedListener,
  requestPurchase,
} from 'react-native-iap';
import type { Purchase, PurchaseError, PurchaseIOS } from 'react-native-iap';
import type {
  NativePaywallBridge,
  PurchaseResult,
  RestoredTransaction,
} from './nativePaywallBridge';

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

export class IapPaywallBridge implements NativePaywallBridge {
  async priceFor(productId: string): Promise<string> {
    const products =
      (await fetchProducts({ skus: [productId], type: 'subs' })) ?? [];
    const price = products[0]?.displayPrice;
    if (price == null)
      throw new Error(`No product found for id "${productId}"`);
    return price;
  }

  async purchase(productId: string): Promise<PurchaseResult> {
    return new Promise<PurchaseResult>((resolve, reject) => {
      const updatedSubscription = purchaseUpdatedListener(
        (purchase: Purchase) => {
          if (purchase.productId !== productId) return;
          cleanup();
          // Deliberately not awaited: this listener callback itself isn't
          // awaited by its caller, so there's nothing to block on besides
          // the .finally() below, which resolves the outer Promise either way.
          // eslint-disable-next-line no-void
          void finishTransaction({ purchase, isConsumable: false })
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

      const errorSubscription = purchaseErrorListener(
        (error: PurchaseError) => {
          if (error.productId != null && error.productId !== productId) return;
          cleanup();
          if (error.code === ErrorCode.UserCancelled) {
            resolve({ outcome: 'cancelled' });
          } else if (error.code === ErrorCode.Pending) {
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

      requestPurchase({
        request: { apple: { sku: productId } },
        type: 'subs',
      }).catch((error: unknown) => {
        cleanup();
        reject(error instanceof Error ? error : new Error(String(error)));
      });
    });
  }

  async restore(): Promise<RestoredTransaction[]> {
    const purchases = await getAvailablePurchases();
    const restored: RestoredTransaction[] = [];
    for (const purchase of purchases) {
      try {
        await finishTransaction({ purchase, isConsumable: false });
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
