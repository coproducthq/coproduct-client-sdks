import SwiftUI
import WebKit

/// Renders and drives one onboarding flow, resolved from `flagKey` via
/// `client` exactly the way any other flag resolves. Shows `fallbackSplash`
/// (a plain `ProgressView` by default) until the shell is assembled and the
/// WebView has loaded it -- and indefinitely if the flag never resolves or
/// the flow can't be fetched, matching both references' precedent of no
/// `onLoadError`-style callback for onboarding.
public struct CoproductOnboardingFlow<Splash: View>: View {
    let flagKey: String
    let client: CoproductClient
    let onEvent: (@Sendable (String, String, [String: [String]]) async -> Void)?
    let onRequestPermission: (@Sendable (String) async -> Void)?
    let onOpenUrl: (@Sendable (String) async -> Void)?
    let onShowPaywall: (@Sendable (String) async -> Void)?
    let onNativeOperation: (@Sendable (String, [String: String]) async throws -> [String: String])?
    let fallbackSplash: Splash

    @State private var boot: Boot?

    struct Boot {
        let html: String
        let runtime: FlowRuntime
    }

    public init(
        flagKey: String,
        client: CoproductClient,
        onEvent: (@Sendable (String, String, [String: [String]]) async -> Void)? = nil,
        onRequestPermission: (@Sendable (String) async -> Void)? = nil,
        onOpenUrl: (@Sendable (String) async -> Void)? = nil,
        onShowPaywall: (@Sendable (String) async -> Void)? = nil,
        onNativeOperation: (@Sendable (String, [String: String]) async throws -> [String: String])? = nil,
        @ViewBuilder fallbackSplash: () -> Splash = { ProgressView() }
    ) {
        self.flagKey = flagKey
        self.client = client
        self.onEvent = onEvent
        self.onRequestPermission = onRequestPermission
        self.onOpenUrl = onOpenUrl
        self.onShowPaywall = onShowPaywall
        self.onNativeOperation = onNativeOperation
        self.fallbackSplash = fallbackSplash()
    }

    public var body: some View {
        Group {
            if let boot {
                OnboardingWebView(html: boot.html, runtime: boot.runtime)
                    .overlay(alignment: .bottomTrailing) {
                        #if DEBUG
                        DebugFlowDrawer(
                            onRestartFlow: { Task { await rebuild(clearProgress: true) } },
                            onRefresh: { Task { await rebuild(clearProgress: false) } }
                        )
                        #endif
                    }
            } else {
                fallbackSplash
            }
        }
        .task { await bootIfNeeded() }
    }

    private func bootIfNeeded() async {
        guard boot == nil else { return }
        guard let flowId = client.resolveStringFlag(flagKey) else { return }
        guard let graph = await client.fetchOnboardingFlow(flowId) else { return }

        let progressStore = LocalProgressStore()
        let progress = progressStore.load(flowId: flowId)
        let runtime = FlowRuntime(
            client: client, progressStore: progressStore, flowId: flowId, flowVersion: progress?.version ?? 1,
            onEvent: onEvent, onRequestPermission: onRequestPermission, onOpenUrl: onOpenUrl,
            onShowPaywall: onShowPaywall, onNativeOperation: onNativeOperation
        )
        let html = runtime.buildShellHtml(
            graph: graph, flowId: flowId, initialScreenId: progress?.screenId,
            initialAnswers: progress?.answers ?? [:], platformScriptJs: await Self.loadPlatformScript()
        )
        boot = Boot(html: html, runtime: runtime)
    }

    private func rebuild(clearProgress: Bool) async {
        if clearProgress {
            if let flowId = client.resolveStringFlag(flagKey) {
                LocalProgressStore().clear(flowId: flowId)
            }
        } else {
            await client.refresh()
        }
        boot = nil
        await bootIfNeeded()
    }

    /// Loads the platform script bundled as this package's own generated
    /// source. Stays `async`-shaped for call-site parity with RN/Flutter's
    /// `loadPlatformScript`, even though this implementation does zero I/O.
    public static func loadPlatformScript() async -> String {
        onboardingPlatformScriptJs
    }
}

/// Owns the `WKWebView` that renders an already-assembled shell. Receives
/// the shell html and the already-constructed `FlowRuntime` as plain
/// values -- it never computes either itself, so it stays a thin rendering
/// layer over logic `FlowRuntimeTests` already covers.
private struct OnboardingWebView: UIViewRepresentable {
    let html: String
    let runtime: FlowRuntime

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.configure(webView: webView, runtime: runtime)
        context.coordinator.loadedHtml = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.configure(webView: webView, runtime: runtime)
        guard context.coordinator.loadedHtml != html else { return }
        context.coordinator.loadedHtml = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var currentRuntime: FlowRuntime?
        var loadedHtml: String?

        func configure(webView: WKWebView, runtime: FlowRuntime) {
            self.webView = webView
            currentRuntime = runtime
            runtime.attachResolver { [weak webView] requestId, response in
                let requestIdJson = (try? JSONEncoder().encode(requestId)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(requestId)\""
                let responseJson = (try? JSONEncoder().encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                await MainActor.run {
                    webView?.evaluateJavaScript("window.__coproductResolveRequest__(\(requestIdJson), \(responseJson));")
                }
            }
        }

        func webView(
            _: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url?.absoluteString ?? ""
            guard url.hasPrefix("coproduct-action:") else { return .allow }
            Task { [weak self] in await self?.currentRuntime?.handleNavigationRequest(url) }
            return .cancel
        }
    }
}
