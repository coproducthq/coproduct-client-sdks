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
/// localized price, its introductory offer (or `nil`), and the store's
/// localized product name (or `nil`). Encodes to the
/// `__coproductSetPackages__` value shape
/// `{ "price": String, "intro": { ... } | null, "title"?: String }`.
/// `title` fills a paywall's optional `data-cp-title-for` slot; it is omitted
/// when `nil`, so a page keeps the author's fallback text.
public struct PaywallPackageRuntime: Equatable, Sendable, Encodable {
    public let price: String
    public let intro: PaywallIntroOffer?
    public let title: String?

    public init(price: String, intro: PaywallIntroOffer?, title: String? = nil) {
        self.price = price
        self.intro = intro
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case price
        case intro
        case title
    }

    // Encodes `intro` explicitly rather than relying on the synthesized
    // conformance's `encodeIfPresent`, which would omit the key entirely for
    // `nil`. The bridge shape requires an explicit `"intro":null` so the
    // WebView can distinguish "no offer" from a missing field.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(price, forKey: .price)
        try container.encode(intro, forKey: .intro)
        try container.encodeIfPresent(title, forKey: .title)
    }
}
