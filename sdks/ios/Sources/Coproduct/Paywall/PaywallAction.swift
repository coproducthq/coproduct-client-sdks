import Foundation

/// The native-capability actions a paywall's platform script can trigger
/// by navigating to a `coproduct-action:` URL, intercepted by the WebView's
/// navigation delegate and never actually navigated.
public enum PaywallAction: Equatable, Sendable {
    case purchase(packageKey: String)
    case restore
    case dismiss
}

/// Parses a `coproduct-action:<action>?<query>` URL for the paywall's
/// action set. Returns `nil` for any URL without that prefix, an
/// unrecognized action, or a `purchase` missing a non-empty `packageKey`.
func parsePaywallAction(_ url: String) -> PaywallAction? {
    let scheme = "coproduct-action:"
    guard url.hasPrefix(scheme) else { return nil }
    let withoutScheme = String(url.dropFirst(scheme.count))
    let parts = withoutScheme.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let action = String(parts[0])
    let query = parts.count > 1 ? String(parts[1]) : ""
    let params = queryParams(from: query)

    switch action {
    case "purchase":
        guard let packageKey = params["packageKey"], !packageKey.isEmpty else { return nil }
        return .purchase(packageKey: packageKey)
    case "restore":
        return .restore
    case "dismiss":
        return .dismiss
    default:
        return nil
    }
}
