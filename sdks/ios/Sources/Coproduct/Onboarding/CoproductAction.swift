import Foundation

/// The native-capability actions an onboarding flow's platform script can
/// trigger by navigating to a `coproduct-action:` URL, intercepted by the
/// WebView's navigation delegate and never actually navigated.
public enum CoproductAction: Equatable, Sendable {
    case requestPermission(permission: String)
    case openUrl(url: String)
    case dismiss
    case complete
    case showPaywall(paywallId: String)
    case request(operation: String, requestId: String, params: [String: String])
    case track(event: String, screenId: String, answers: [String: [String]])
}

/// Parses a `coproduct-action:<action>?<query>` URL. Returns `nil` for any
/// URL without that prefix (real navigation should proceed) or for an
/// unrecognized action name.
func parseCoproductAction(_ url: String) -> CoproductAction? {
    let scheme = "coproduct-action:"
    guard url.hasPrefix(scheme) else { return nil }
    let withoutScheme = String(url.dropFirst(scheme.count))
    let parts = withoutScheme.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let action = String(parts[0])
    let query = parts.count > 1 ? String(parts[1]) : ""
    let params = queryParams(from: query)

    switch action {
    case "requestPermission":
        return .requestPermission(permission: params["permission"] ?? "")
    case "openUrl":
        return .openUrl(url: params["url"] ?? "")
    case "dismiss":
        return .dismiss
    case "complete":
        return .complete
    case "showPaywall":
        return .showPaywall(paywallId: params["paywallId"] ?? "")
    case "request":
        var requestParams: [String: String] = [:]
        for (key, value) in params where key.hasPrefix("param_") {
            requestParams[String(key.dropFirst("param_".count))] = value
        }
        return .request(
            operation: params["operation"] ?? "",
            requestId: params["requestId"] ?? "",
            params: requestParams
        )
    case "track":
        let answers: [String: [String]]
        if let rawAnswers = params["answers"],
           let data = rawAnswers.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            answers = decoded
        } else {
            answers = [:]
        }
        return .track(event: params["event"] ?? "", screenId: params["screenId"] ?? "", answers: answers)
    default:
        return nil
    }
}

/// Decodes a `key=value&key2=value2` query string with percent-decoding,
/// matching `URLSearchParams`'s behavior in the reference implementations.
/// Shared by both `coproduct-action:` parsers (onboarding and paywall).
func queryParams(from query: String) -> [String: String] {
    var result: [String: String] = [:]
    for pair in query.split(separator: "&") where !pair.isEmpty {
        let keyValue = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let key = String(keyValue[0]).removingPercentEncoding ?? String(keyValue[0])
        let value = keyValue.count > 1 ? (String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])) : ""
        result[key] = value
    }
    return result
}
