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
}

// One transaction react-native-iap's getAvailablePurchases reported during
// a restore. Unlike PurchaseResult, every field is required -- restore only
// ever reports verified, completed transactions.
export interface RestoredTransaction {
  transactionId: string;
  productId: string;
  purchaseDate: Date;
  expirationDate?: Date;
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
// localized price and its introductory offer (or null).
export interface PaywallPackageRuntime {
  price: string;
  intro: PaywallIntroOffer | null;
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
  restore(): Promise<RestoredTransaction[]>;
}
