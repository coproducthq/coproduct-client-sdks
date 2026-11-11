/// What kind of store product a packageKey resolves to. Determines both
/// the Play Billing product type (subscription -> SUBS, consumable/lifetime
/// -> INAPP) and whether a successful purchase is consumed or acknowledged
/// on Android. iOS's StoreKit2 plugin receives this value and ignores it --
/// consumption has no StoreKit2 equivalent. Mirrors the Coproduct platform's
/// own Product.kind and RN's PackageKind
/// (sdks/react-native/coproduct/src/paywall/nativePaywallBridge.ts).
enum PackageKind { subscription, consumable, lifetime }

/// What StoreKit2 or the Play Billing bridge reported for one purchase
/// attempt. cancelled and pending are normal outcomes, not errors --
/// CoproductPaywall surfaces every outcome through onPurchaseResult,
/// reserving onPurchaseError for cases the store never itself reports as
/// "the purchase happened."
enum PurchaseOutcome { success, cancelled, pending }

class PurchaseResult {
  final PurchaseOutcome outcome;
  final String? transactionId;
  final String? productId;
  final DateTime? purchaseDate;
  final DateTime? expirationDate;

  const PurchaseResult({
    required this.outcome,
    this.transactionId,
    this.productId,
    this.purchaseDate,
    this.expirationDate,
  });
}

/// One transaction StoreKit2's Transaction.currentEntitlements reported
/// during a restore. Unlike PurchaseResult, every field is required --
/// restore only ever reports verified, completed transactions.
class RestoredTransaction {
  final String transactionId;
  final String productId;
  final DateTime purchaseDate;
  final DateTime? expirationDate;

  const RestoredTransaction({
    required this.transactionId,
    required this.productId,
    required this.purchaseDate,
    this.expirationDate,
  });
}

/// Thrown when no native paywall plugin is registered for this platform.
class PaywallBridgeUnavailable implements Exception {
  const PaywallBridgeUnavailable();

  @override
  String toString() =>
      'PaywallBridgeUnavailable: no native paywall plugin is registered for this platform';
}

/// One package's introductory offer as resolved natively, or its absence.
/// [eligible] is per-user: PaywallRuntime only ever sends an intro when the
/// store reports this user eligible, so the WebView can reveal trial copy
/// without re-checking. Encodes to the bridge shape
/// `{ "eligible": bool, "label": String }`. Mirrors iOS's
/// `PaywallIntroOffer` (sdks/ios/Sources/Coproduct/Paywall/PaywallPackageRuntime.swift)
/// and RN's `PaywallIntroOffer`
/// (sdks/react-native/coproduct/src/paywall/nativePaywallBridge.ts).
class PaywallIntroOffer {
  final bool eligible;
  final String label;

  const PaywallIntroOffer({required this.eligible, required this.label});

  Map<String, Object?> toChannelMap() => {'eligible': eligible, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is PaywallIntroOffer &&
      other.eligible == eligible &&
      other.label == label;

  @override
  int get hashCode => Object.hash(eligible, label);
}

/// One package's live store data for a single paywall render: the regular
/// localized price and its introductory offer (or null). Encodes to the
/// `__coproductSetPackages__` value shape
/// `{ "price": String, "intro": { ... } | null }`.
class PaywallPackageRuntime {
  final String price;
  final PaywallIntroOffer? intro;

  const PaywallPackageRuntime({required this.price, this.intro});

  // Encodes intro explicitly as `null` rather than omitting the key, so the
  // WebView can distinguish "no offer" from a missing field -- mirrors
  // PaywallPackageRuntime.swift's explicit `encode` override.
  Map<String, Object?> toJson() => {
    'price': price,
    'intro': intro?.toChannelMap(),
  };

  @override
  bool operator ==(Object other) =>
      other is PaywallPackageRuntime &&
      other.price == price &&
      other.intro == intro;

  @override
  int get hashCode => Object.hash(price, intro);
}

/// The native-capability contract PaywallRuntime drives. Deliberately not
/// MethodChannel-shaped, so PaywallRuntime stays unit-testable against a
/// fake implementation -- the same testability property
/// coproduct_onboarding's CoproductClient gives FlowRuntime.
abstract interface class NativePaywallBridge {
  Future<String> priceFor(String productId, PackageKind kind);
  Future<PurchaseResult> purchase(String productId, PackageKind kind);
  Future<List<RestoredTransaction>> restore();
}

/// Optional capability: a bridge that resolves a full package (the regular
/// price plus the eligible introductory offer), not just a price. The built-in
/// [MethodChannelPaywallBridge] implements it. A bridge that does not is driven
/// through [NativePaywallBridge.priceFor] and rendered as a price-only package
/// with no intro offer, so a custom bridge written before packages existed
/// keeps working unchanged.
///
/// This lives on its own interface, not on [NativePaywallBridge], on purpose.
/// Adding a required method to the public NativePaywallBridge would break every
/// existing implementer, so PaywallRuntime checks `is PackageResolvingBridge`
/// instead. It is Dart's equivalent of RN's optional `packageFor?` and iOS's
/// protocol-extension default. It extends NativePaywallBridge so the `is` check
/// in PaywallRuntime promotes the bridge (Dart only promotes to a subtype).
abstract interface class PackageResolvingBridge implements NativePaywallBridge {
  Future<PaywallPackageRuntime> packageFor(String productId, PackageKind kind);
}
