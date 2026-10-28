import SwiftUI
import UIKit
import WebKit

/// Reported through `onLoadError` when the paywall itself could not be
/// fetched -- never a blank or broken WebView.
public struct PaywallLoadError: Equatable, Sendable {
    public let message: String
}

/// Minimal flag-reading surface `prefetchPlacements` needs to resolve a
/// placement flag to a paywallId. Declared here so the paywall feature keeps
/// its independence from the base flag SDK; the process-wide `Coproduct` flag
/// surface backs the default reader. Mirrors the React Native and Flutter
/// `FlagReader`.
public protocol FlagReader {
    func getString(_ key: String, default defaultValue: String) -> String
}

/// Resolves placement flags through the process-wide `Coproduct` flag surface.
/// The default reader for `prefetchPlacements`, so a host warms placements
/// without wiring up a flag-reading object of its own; a test injects a fake
/// instead.
struct CoproductFlagReader: FlagReader {
    func getString(_ key: String, default defaultValue: String) -> String {
        Coproduct.getString(key, default: defaultValue)
    }
}

/// Renders and drives one resolved paywall: fetches it, loads its html into
/// a `WKWebView`, resolves and injects live StoreKit2 prices, and completes
/// a purchase or restore when the user taps a cta.
public struct CoproductPaywall: View {
    let paywallId: String
    let appUserId: String
    let sdkKey: String
    let envSlug: String?
    let onPurchaseResult: (@Sendable (PurchaseResult, [Entitlement]) -> Void)?
    let onPurchaseError: (@Sendable (PaywallPurchaseError) -> Void)?
    let onDismiss: (@Sendable () -> Void)?
    let onLoadError: (@Sendable (PaywallLoadError) -> Void)?
    let client: PaywallClient?
    let bridge: NativePaywallBridge?

    public init(
        paywallId: String,
        appUserId: String,
        sdkKey: String,
        envSlug: String? = nil,
        onPurchaseResult: (@Sendable (PurchaseResult, [Entitlement]) -> Void)? = nil,
        onPurchaseError: (@Sendable (PaywallPurchaseError) -> Void)? = nil,
        onDismiss: (@Sendable () -> Void)? = nil,
        onLoadError: (@Sendable (PaywallLoadError) -> Void)? = nil,
        client: PaywallClient? = nil,
        bridge: NativePaywallBridge? = nil
    ) {
        self.paywallId = paywallId
        self.appUserId = appUserId
        self.sdkKey = sdkKey
        self.envSlug = envSlug
        self.onPurchaseResult = onPurchaseResult
        self.onPurchaseError = onPurchaseError
        self.onDismiss = onDismiss
        self.onLoadError = onLoadError
        self.client = client
        self.bridge = bridge
    }

    public var body: some View {
        PaywallWebViewHost(
            paywallId: paywallId, appUserId: appUserId, sdkKey: sdkKey, envSlug: envSlug,
            onPurchaseResult: onPurchaseResult, onPurchaseError: onPurchaseError,
            onDismiss: onDismiss, onLoadError: onLoadError,
            client: client ?? HttpPaywallClient(sdkKey: sdkKey, envSlug: envSlug),
            bridge: bridge ?? StoreKitPaywallBridge()
        )
    }

    /// Loads the platform script bundled as this package's own generated
    /// source. Stays `async`-shaped for call-site parity with RN/Flutter's
    /// `loadPlatformScript`, even though this implementation does zero I/O.
    public static func loadPlatformScript() async -> String {
        paywallPlatformScriptJs
    }

    /// Fetches a paywall's snapshot and holds it in a process-level cache so a
    /// later `CoproductPaywall` for the same id and environment renders without
    /// a network round-trip. Call this once at app launch (right after the SDK
    /// is initialized) for any paywall the user is likely to reach, so the
    /// first open is instant instead of showing a spinner while the snapshot
    /// downloads.
    ///
    /// Best-effort: a failed fetch is swallowed, leaving the cache cold so the
    /// paywall's own boot fetches and reports errors normally. Safe to call
    /// more than once; a later call simply refreshes the cached snapshot.
    public static func prefetch(
        paywallId: String,
        sdkKey: String,
        envSlug: String? = nil,
        client: PaywallClient? = nil
    ) async {
        let client = client ?? HttpPaywallClient(sdkKey: sdkKey, envSlug: envSlug)
        await snapshotCache.warm(snapshotCacheKey(paywallId, envSlug)) {
            await client.fetchPaywall(paywallId)
        }
    }

    /// Warms every paywall the given placement flags currently resolve to. A
    /// placement is an ordinary string flag whose value is a paywallId,
    /// resolved here through `client` (the process-wide flag surface by
    /// default) so targeting is respected. Call once at launch with the app's
    /// paywall flag keys. Best-effort; failures leave the cache cold.
    public static func prefetchPlacements(
        flagKeys: [String],
        sdkKey: String,
        envSlug: String? = nil,
        client: FlagReader? = nil,
        paywallClient: PaywallClient? = nil
    ) async {
        let reader: FlagReader = client ?? CoproductFlagReader()
        let paywallClient = paywallClient ?? HttpPaywallClient(sdkKey: sdkKey, envSlug: envSlug)
        var seen = Set<String>()
        await withTaskGroup(of: Void.self) { group in
            for flagKey in flagKeys {
                let paywallId = reader.getString(flagKey, default: "")
                if paywallId.isEmpty || seen.contains(paywallId) { continue }
                seen.insert(paywallId)
                group.addTask {
                    await snapshotCache.warm(snapshotCacheKey(paywallId, envSlug)) {
                        await paywallClient.fetchPaywall(paywallId)
                    }
                }
            }
        }
    }
}

/// Owns the `WKWebView` and its navigation delegate, fetches the paywall,
/// and drives a `PaywallRuntime`. A `UIViewRepresentable` rather than a
/// plain `View` body because `WKWebView` is a `UIView`, not SwiftUI-native.
struct PaywallWebViewHost: UIViewRepresentable {
    let paywallId: String
    let appUserId: String
    let sdkKey: String
    let envSlug: String?
    let onPurchaseResult: (@Sendable (PurchaseResult, [Entitlement]) -> Void)?
    let onPurchaseError: (@Sendable (PaywallPurchaseError) -> Void)?
    let onDismiss: (@Sendable () -> Void)?
    let onLoadError: (@Sendable (PaywallLoadError) -> Void)?
    let client: PaywallClient
    let bridge: NativePaywallBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(
            paywallId: paywallId, appUserId: appUserId, envSlug: envSlug,
            onPurchaseResult: onPurchaseResult, onPurchaseError: onPurchaseError,
            onDismiss: onDismiss, onLoadError: onLoadError, client: client, bridge: bridge
        )
    }

    // The WebView is mounted hidden and transparent beneath a loading
    // indicator, and revealed only once it has painted its html and had live
    // prices applied (see Coordinator.reveal). Until then the user never sees
    // the WebView's blank first paint (a white flash) nor the half-rendered,
    // price-less intermediate frame.
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        // Transparent so the WebView's own blank first paint is never a white
        // flash: while hidden there is nothing to see through to but the host
        // background, and the paywall html paints its own background once loaded.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.alpha = 0
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        context.coordinator.attach(webView: webView, spinner: spinner)
        return container
    }

    func updateUIView(_: UIView, context _: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let paywallId: String
        private let appUserId: String
        private let envSlug: String?
        private let onPurchaseResult: (@Sendable (PurchaseResult, [Entitlement]) -> Void)?
        private let onPurchaseError: (@Sendable (PaywallPurchaseError) -> Void)?
        private let onDismiss: (@Sendable () -> Void)?
        private let onLoadError: (@Sendable (PaywallLoadError) -> Void)?
        private let client: PaywallClient
        private let bridge: NativePaywallBridge
        private weak var webView: WKWebView?
        private weak var spinner: UIActivityIndicatorView?
        private var runtime: PaywallRuntime?
        private var loadedSnapshot: PaywallSnapshot?
        private var revealed = false
        private var revealTask: Task<Void, Never>?

        init(
            paywallId: String, appUserId: String, envSlug: String?,
            onPurchaseResult: (@Sendable (PurchaseResult, [Entitlement]) -> Void)?,
            onPurchaseError: (@Sendable (PaywallPurchaseError) -> Void)?,
            onDismiss: (@Sendable () -> Void)?,
            onLoadError: (@Sendable (PaywallLoadError) -> Void)?,
            client: PaywallClient, bridge: NativePaywallBridge
        ) {
            self.paywallId = paywallId
            self.appUserId = appUserId
            self.envSlug = envSlug
            self.onPurchaseResult = onPurchaseResult
            self.onPurchaseError = onPurchaseError
            self.onDismiss = onDismiss
            self.onLoadError = onLoadError
            self.client = client
            self.bridge = bridge
        }

        func attach(webView: WKWebView, spinner: UIActivityIndicatorView) {
            self.webView = webView
            self.spinner = spinner
            Task { await boot() }
        }

        /// Reveals the fully-formed, priced paywall in a single cut from the
        /// spinner. Idempotent: the first of the paint signal, the price
        /// signal, and the hang guard wins and the rest are no-ops.
        private func reveal() {
            guard !revealed else { return }
            revealed = true
            revealTask?.cancel()
            revealTask = nil
            spinner?.stopAnimating()
            spinner?.isHidden = true
            webView?.alpha = 1
        }

        private func boot() async {
            let snapshot = await snapshotCache.resolve(snapshotCacheKey(paywallId, envSlug)) { [client, paywallId] in
                await client.fetchPaywall(paywallId)
            }
            guard let snapshot else {
                onLoadError?(PaywallLoadError(message: "Paywall not found for this environment."))
                return
            }
            loadedSnapshot = snapshot

            let runtime = PaywallRuntime(
                bridge: bridge, client: client, appUserId: appUserId,
                setPrices: { [weak self] prices in await self?.injectPrices(prices) },
                onPurchaseResult: { [weak self] result, entitlements in
                    // `PaywallRuntime` holds these as plain synchronous
                    // `@Sendable` closures with no actor affinity, but the
                    // work they do here (reporting into the WebView,
                    // invoking the host callback) belongs on the
                    // `@MainActor`-isolated coordinator -- hop over with a
                    // `Task` rather than widening the Coordinator's own
                    // isolation.
                    guard let self else { return }
                    Task { @MainActor in
                        self.report(state: Self.resultState(for: result))
                        self.onPurchaseResult?(result, entitlements)
                    }
                },
                onPurchaseError: { [weak self] error in
                    guard let self else { return }
                    Task { @MainActor in
                        self.report(state: "fail")
                        self.onPurchaseError?(error)
                    }
                },
                onDismiss: { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in self.onDismiss?() }
                }
            )
            self.runtime = runtime

            let shellHtml = PaywallShellAssembler.assemble(
                bodyHtml: snapshot.html, platformScriptJs: await CoproductPaywall.loadPlatformScript()
            )
            webView?.loadHTMLString(shellHtml, baseURL: nil)

            // Hang guard only. The paywall is revealed when its content has
            // actually painted (didFinish) or its prices land (injectPrices) --
            // never on a fixed delay, because the WebView is transparent while
            // hidden, so revealing it before it has painted shows through to
            // the host background until paint catches up. This timer exists
            // solely so a WebView that never finishes (load hung, no network)
            // still reveals rather than spinning forever; it is deliberately
            // far longer than any real load.
            revealTask?.cancel()
            revealTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self?.reveal()
            }
        }

        private static func resultState(for result: PurchaseResult) -> (state: String, message: String?) {
            switch result.outcome {
            case .success: return ("success", nil)
            case .pending: return ("cancel", "Waiting for approval.")
            case .cancelled: return ("cancel", nil)
            }
        }

        private func report(state: (state: String, message: String?)) {
            reportToWebView(state: state.state, message: state.message)
        }

        private func report(state: String) {
            reportToWebView(state: state, message: nil)
        }

        private func reportToWebView(state: String, message: String?) {
            webView?.evaluateJavaScript(
                "window.__coproductOnPurchaseResult__(\(jsLiteral(state)), \(jsLiteral(message)));"
            )
        }

        private func injectPrices(_ prices: [String: String]) async {
            guard let data = try? JSONEncoder().encode(prices), let json = String(data: data, encoding: .utf8) else { return }
            // Explicit `completionHandler: nil` disambiguates from the
            // `async throws` overload of `evaluateJavaScript`, which this
            // `async` function would otherwise resolve to -- this call
            // stays fire-and-forget, matching `reportToWebView` below.
            webView?.evaluateJavaScript("window.__coproductSetPrices__(\(json));", completionHandler: nil)
            // Prices are the last thing to land, so the paywall is now fully
            // formed -- reveal it. The didFinish fallback still covers the case
            // where prices never resolve (e.g. the store is unreachable).
            reveal()
        }

        /// Encodes a Swift string as a properly escaped JS string literal
        /// (quotes, backslashes, newlines) for embedding directly in an
        /// `evaluateJavaScript` call, or `"null"` for a `nil` message.
        private func jsLiteral(_ value: String?) -> String {
            guard let value else { return "null" }
            guard let data = try? JSONEncoder().encode(value), let literal = String(data: data, encoding: .utf8) else {
                return "null"
            }
            return literal
        }

        // Price injection runs JS against the page's own global, so it must
        // wait for the inline <script> to have actually executed -- firing
        // right after loadHTMLString returns (before the WebView has
        // painted) races a cold WebView's first paint and can silently
        // miss, especially since a cached StoreKit price can resolve
        // faster than that paint.
        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            // The whole document has loaded, so reveal if prices have not
            // already. injectPrices reveals sooner once prices land.
            reveal()
            guard let snapshot = loadedSnapshot, let runtime else { return }
            Task { await runtime.onSnapshotLoaded(snapshot) }
        }

        func webView(
            _: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url?.absoluteString ?? ""
            guard url.hasPrefix("coproduct-action:") else { return .allow }
            Task { await runtime?.handleNavigationRequest(url) }
            return .cancel
        }
    }
}
