// What a purchase unlocks, as resolved server-side and returned by
// POST /v1/purchases and GET /v1/entitlements. Mirrors
// sdks/flutter/coproduct/lib/src/paywall/models/entitlement.dart.
export interface Entitlement {
  entitlementId: string;
  isActive: boolean;
  expiresAt?: Date;
  willRenew: boolean;
  source: string;
}

export function parseEntitlement(json: Record<string, unknown>): Entitlement {
  return {
    entitlementId: json.entitlementId as string,
    isActive: json.isActive as boolean,
    expiresAt:
      json.expiresAt == null ? undefined : new Date(json.expiresAt as string),
    willRenew: json.willRenew as boolean,
    source: json.source as string,
  };
}
