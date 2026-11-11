import Foundation

/// One package's introductory offer as resolved natively, or its absence.
/// `eligible` is per-user: `PaywallRuntime` only ever sends an intro when the
/// store reports this user eligible, so the WebView can reveal trial copy
/// without re-checking. Encodes to the bridge shape
/// `{ "eligible": Bool, "label": String }`.
public struct PaywallIntroOffer: Equatable, Sendable, Encodable {
    public let eligible: Bool
    public let label: String

    public init(eligible: Bool, label: String) {
        self.eligible = eligible
        self.label = label
    }
}

/// One package's live store data for a single paywall render: the regular
/// localized price and its introductory offer (or `nil`). Encodes to the
/// `__coproductSetPackages__` value shape
/// `{ "price": String, "intro": { ... } | null }`.
public struct PaywallPackageRuntime: Equatable, Sendable, Encodable {
    public let price: String
    public let intro: PaywallIntroOffer?

    public init(price: String, intro: PaywallIntroOffer?) {
        self.price = price
        self.intro = intro
    }

    private enum CodingKeys: String, CodingKey {
        case price
        case intro
    }

    // Encodes `intro` explicitly rather than relying on the synthesized
    // conformance's `encodeIfPresent`, which would omit the key entirely for
    // `nil`. The bridge shape requires an explicit `"intro":null` so the
    // WebView can distinguish "no offer" from a missing field.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(price, forKey: .price)
        try container.encode(intro, forKey: .intro)
    }
}
