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

// The native-capability contract PaywallRuntime drives. Deliberately not
// react-native-iap-shaped, so PaywallRuntime stays unit-testable against a
// fake implementation.
export interface NativePaywallBridge {
  priceFor(productId: string): Promise<string>;
  purchase(productId: string): Promise<PurchaseResult>;
  restore(): Promise<RestoredTransaction[]>;
}
