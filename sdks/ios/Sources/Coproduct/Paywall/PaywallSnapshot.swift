import Foundation

/// What kind of store product a packageKey resolves to. StoreKit2's own
/// purchase call is kind-agnostic; this exists purely for cross-platform
/// protocol-contract parity with RN/Flutter's `NativePaywallBridge`.
public enum PackageKind: String, Equatable, Sendable {
    case subscription
    case consumable
    case lifetime
}

extension PackageKind: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "consumable": self = .consumable
        case "lifetime": self = .lifetime
        default: self = .subscription
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

/// One purchase option a paywall offers, e.g. monthly or annual. `packageKey`
/// matches the backend's abstract key; native resolves it to a real store
/// product id via the sibling `PaywallPackageRef` map, never from this type
/// directly.
public struct PaywallCta: Codable, Equatable, Sendable {
    public let packageKey: String
    public let label: String
}

/// A paywall's authored content. `html` is author-written markup, not
/// assembled from structured fields.
public struct PaywallContent: Codable, Equatable, Sendable {
    public let offeringKey: String
    public let ctas: [PaywallCta]
    public let html: String
}

/// One packageKey's store product ids, as resolved server-side from the
/// offering the paywall's `content.offeringKey` points at. Every product id
/// field is optional -- an offering may only have an iOS product configured.
/// `kind` absent or unrecognized defaults to `.subscription`, preserving
/// this feature's original subscription-only behavior for a server that
/// predates consumable support.
public struct PaywallPackageRef: Codable, Equatable, Sendable {
    public let iosProductId: String?
    public let androidProductId: String?
    public let webProductId: String?
    public let kind: PackageKind

    enum CodingKeys: String, CodingKey {
        case iosProductId, androidProductId, webProductId, kind
    }

    public init(iosProductId: String?, androidProductId: String?, webProductId: String?, kind: PackageKind) {
        self.iosProductId = iosProductId
        self.androidProductId = androidProductId
        self.webProductId = webProductId
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iosProductId = try container.decodeIfPresent(String.self, forKey: .iosProductId)
        androidProductId = try container.decodeIfPresent(String.self, forKey: .androidProductId)
        webProductId = try container.decodeIfPresent(String.self, forKey: .webProductId)
        kind = try container.decodeIfPresent(PackageKind.self, forKey: .kind) ?? .subscription
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(iosProductId, forKey: .iosProductId)
        try container.encodeIfPresent(androidProductId, forKey: .androidProductId)
        try container.encodeIfPresent(webProductId, forKey: .webProductId)
        try container.encode(kind, forKey: .kind)
    }
}

/// The resolved paywall a device fetches.
public struct PaywallSnapshot: Codable, Equatable, Sendable {
    public let paywallId: String
    public let version: Int
    public let templateType: String
    public let content: PaywallContent
    public let packages: [String: PaywallPackageRef]
    public let html: String
}
