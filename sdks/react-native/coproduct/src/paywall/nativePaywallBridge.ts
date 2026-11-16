// What kind of store product a packageKey resolves to. Determines both the
// react-native-iap request type ('subs' for subscription, 'in-app' for
// consumable/lifetime) and whether the transaction gets consumed on finish
// (consumable only -- lets the same SKU be re-bought, e.g. a points pack).
// Mirrors the Coproduct platform's own Product.kind
// (SUBSCRIPTION/CONSUMABLE/LIFETIME). Defaults to 'subscription' wherever
// unspecified, preserving this feature's original subscription-only
// behavior exactly.
export type PackageKind = 'subscription' | 'consumable' | 'lifetime';

// What react-native-iap (StoreKit2 under the hood) reported for one
// purchase attempt. cancelled and pending are normal outcomes, not errors
// -- CoproductPaywall surfaces every outcome through onPurchaseResult,
// reserving onPurchaseError for cases that never themselves report "the
// purchase happened." Mirrors
// sdks/flutter/coproduct/lib/src/paywall/native_paywall_bridge.dart.
export type PurchaseOutcome = 'success' | 'cancelled' | 'pending';

export interface PurchaseResult {
  outcome: PurchaseOutcome;
  transactionId?: string;
  productId?: string;
  purchaseDate?: Date;
  expirationDate?: Date;
  /**
   * StoreKit 2's signed transaction (its JWS representation), which the
   * server verifies against Apple's root. Undefined on Android, and on a
   * bridge that does not report it.
   */
  signedTransaction?: string;
  /**
   * Google Play's purchase token, which the server checks with Google.
   * Undefined on iOS, and on a bridge that does not report it.
   */
  purchaseToken?: string;
}

// One transaction react-native-iap's getAvailablePurchases reported during
// a restore. Unlike PurchaseResult, every field is required -- restore only
// ever reports verified, completed transactions.
export interface RestoredTransaction {
  transactionId: string;
  productId: string;
  purchaseDate: Date;
  expirationDate?: Date;
  /**
   * The store's own proof of this transaction. See
   * PurchaseResult.signedTransaction.
   */
  signedTransaction?: string;
  /**
   * The store's own proof of this transaction. See
   * PurchaseResult.purchaseToken.
   */
  purchaseToken?: string;
}

// One package's introductory offer as resolved natively, or its absence.
// eligible is per-user: the runtime only ever sends an intro when the store
// reports this user eligible, so the WebView can reveal trial copy without
// re-checking.
export interface PaywallIntroOffer {
  eligible: boolean;
  label: string;
}

// One package's live store data for a single paywall render: the regular
// localized price, its introductory offer (or null), and the store's
// localized product name. title fills a paywall's optional data-cp-title-for
// slot; when absent the page keeps the author's fallback text.
export interface PaywallPackageRuntime {
  price: string;
  intro: PaywallIntroOffer | null;
  title?: string;
}

// The native-capability contract PaywallRuntime drives. Deliberately not
// react-native-iap-shaped, so PaywallRuntime stays unit-testable against a
// fake implementation.
export interface NativePaywallBridge {
  priceFor(productId: string, kind: PackageKind): Promise<string>;
  // Resolves a package's price and, when the store offers one and this user
  // is eligible, its introductory offer. Optional: a bridge that implements
  // only priceFor still works, the runtime falls back to a price-only result.
  packageFor?(productId: string, kind: PackageKind): Promise<PaywallPackageRuntime>;
  purchase(productId: string, kind: PackageKind): Promise<PurchaseResult>;
  /**
   * Purchases a product and tells the store which app user it is for. The
   * store keeps a token derived from appUserId with the transaction
   * (StoreKit's appAccountToken, Play's obfuscatedAccountId) and returns it to
   * the server, which uses it to tell whose purchase this is. Optional: a
   * bridge that implements only purchase still works, the runtime falls back
   * to it and its purchases carry no token.
   */
  purchaseForUser?(
    productId: string,
    kind: PackageKind,
    appUserId: string
  ): Promise<PurchaseResult>;
  restore(): Promise<RestoredTransaction[]>;
}
