/// What a purchase unlocks, as resolved server-side and returned by
/// POST /v1/purchases and GET /v1/entitlements (readEntitlements in
/// apps/api-worker/src/features/paywalls/services/purchases.ts).
class Entitlement {
  final String entitlementId;
  final bool isActive;
  final DateTime? expiresAt;
  final bool willRenew;
  final String source;

  const Entitlement({
    required this.entitlementId,
    required this.isActive,
    this.expiresAt,
    required this.willRenew,
    required this.source,
  });

  factory Entitlement.fromJson(Map<String, dynamic> json) => Entitlement(
    entitlementId: json['entitlementId'] as String,
    isActive: json['isActive'] as bool,
    expiresAt: json['expiresAt'] == null ? null : DateTime.parse(json['expiresAt'] as String),
    willRenew: json['willRenew'] as bool,
    source: json['source'] as String,
  );
}
