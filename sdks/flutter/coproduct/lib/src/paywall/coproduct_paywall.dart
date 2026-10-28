import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import 'http_paywall_client.dart';
import 'method_channel_paywall_bridge.dart';
import 'models/paywall_snapshot.dart';
import 'native_paywall_bridge.dart';
import 'paywall_client.dart';
import 'paywall_runtime.dart';
import 'paywall_shell_assembler.dart';
import 'snapshot_cache.dart';

/// Thrown through [CoproductPaywall.onLoadError] when a paywall can't be
/// fetched -- not found for this environment, or the request itself failed.
class PaywallLoadError {
  final String message;
  const PaywallLoadError(this.message);
}

/// Renders and drives one resolved paywall: fetches it, loads its html into
/// a WebView, resolves and injects live store prices (StoreKit 2 on iOS,
/// Google Play Billing on Android), and completes a purchase or restore when
/// the user taps a cta. [paywallId] is resolved
/// the same way coproduct_onboarding resolves a flowId: from an ordinary
/// flag read, done by the caller before constructing this widget.
class CoproductPaywall extends StatefulWidget {
  final String paywallId;
  final String appUserId;
  final String sdkKey;
  final String platformScriptJs;
  final PurchaseResultCallback? onPurchaseResult;
  final PurchaseErrorCallback? onPurchaseError;
  final void Function(PaywallLoadError error)? onLoadError;
  final void Function()? onDismiss;

  /// When set, and [client] is not overridden, the default HttpPaywallClient
  /// fetches straight from the R2-backed content CDN for this environment
  /// instead of the edge-worker api, with no fallback between the two. Omit
  /// this to keep using the api, unconditionally -- the safe default for a
  /// paywall that may not have been redeployed since this content-CDN path
  /// shipped (see coproduct-platform's R2 content delivery work).
  final String? envSlug;

  /// Overridable for tests. Defaults to the real HTTP client and the real
  /// MethodChannel bridge (StoreKit 2 on iOS, Play Billing on Android).
  final PaywallClient? client;
  final NativePaywallBridge? bridge;

  const CoproductPaywall({
    super.key,
    required this.paywallId,
    required this.appUserId,
    required this.sdkKey,
    required this.platformScriptJs,
    this.envSlug,
    this.onPurchaseResult,
    this.onPurchaseError,
    this.onLoadError,
    this.onDismiss,
    this.client,
    this.bridge,
  });

  /// Loads the platform script bundled as this package's own asset. A host
  /// app calls this once and passes the result into [platformScriptJs]
  /// rather than knowing the asset path itself -- mirrors
  /// CoproductOnboardingFlow.loadPlatformScript.
  static Future<String> loadPlatformScript() => rootBundle.loadString(
    'packages/coproduct/assets/paywall/paywall-platform-script.js',
  );

  /// Fetches a paywall's snapshot and holds it in a process-level cache so a
  /// later [CoproductPaywall] for the same id and environment renders without
  /// a network round-trip. Call this once at app launch (right after the SDK
  /// is initialized) for any paywall the user is likely to reach, so the first
  /// open is instant instead of showing a spinner while the snapshot
  /// downloads.
  ///
  /// Best-effort: a failed fetch is swallowed, leaving the cache cold so the
  /// paywall's own boot fetches and reports errors normally. Safe to call more
  /// than once; a later call simply refreshes the cached snapshot.
  static Future<void> prefetch({
    required String paywallId,
    required String sdkKey,
    String? envSlug,
    PaywallClient? client,
  }) async {
    final c = client ?? HttpPaywallClient(sdkKey: sdkKey, envSlug: envSlug);
    await snapshotCache.warm(
      snapshotCacheKey(paywallId, envSlug),
      () => c.fetchPaywall(paywallId),
    );
  }

  @override
  State<CoproductPaywall> createState() => _CoproductPaywallState();
}

class _CoproductPaywallState extends State<CoproductPaywall> {
  WebViewController? _controller;
  bool _ready = false;
  // The WebView is built hidden and revealed only once it has painted its
  // html and had live prices applied. Until then a loading indicator stays on
  // top, so the user never sees the WebView's blank first paint (a white flash
  // on iOS) nor the half-rendered, price-less intermediate frame.
  bool _visible = false;
  Timer? _revealTimer;

  void _reveal() {
    if (!mounted || _visible) return;
    setState(() => _visible = true);
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final client =
        widget.client ??
        HttpPaywallClient(sdkKey: widget.sdkKey, envSlug: widget.envSlug);
    final bridge = widget.bridge ?? const MethodChannelPaywallBridge();

    final cacheKey = snapshotCacheKey(widget.paywallId, widget.envSlug);
    PaywallSnapshot? snapshot;
    try {
      snapshot = await snapshotCache.resolve(
        cacheKey,
        () => client.fetchPaywall(widget.paywallId),
      );
    } catch (e) {
      widget.onLoadError?.call(PaywallLoadError(e.toString()));
      return;
    }
    if (snapshot == null) {
      widget.onLoadError?.call(
        const PaywallLoadError('Paywall not found for this environment.'),
      );
      return;
    }
    // A local var's null-promotion doesn't persist into a closure declared
    // later in this scope (the onPageFinished callback below) -- binding it
    // to a final makes the non-null type available there too
    final PaywallSnapshot resolvedSnapshot = snapshot;

    Future<void> reportResultToWebView(String state, [String? message]) async {
      try {
        await _controller?.runJavaScript(
          'window.__coproductOnPurchaseResult__(${jsonEncode(state)}, ${jsonEncode(message)})',
        );
      } catch (_) {
        // The WebView may already be torn down by the time this fires
      }
    }

    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: widget.appUserId,
      platform: Platform.isAndroid ? 'ANDROID' : 'IOS',
      setPrices: (prices) async {
        try {
          await _controller?.runJavaScript(
            'window.__coproductSetPrices__(${jsonEncode(prices)})',
          );
        } catch (_) {
          // The WebView may already be torn down by the time prices
          // resolve -- nothing to do
        }
        // Prices are the last thing to land, so the paywall is now fully
        // formed -- reveal it. The onPageFinished fallback below still covers
        // the case where prices never resolve (e.g. the store is unreachable).
        _reveal();
      },
      // The default [data-cp-result] sections (success/cancel/fail) own
      // showing the outcome and, for cancel/fail, waiting for the user's own
      // dismiss tap -- success auto-dismisses itself after a brief hold.
      // onDismiss (not onPurchaseResult/onPurchaseError) is therefore the
      // single place a host app should navigate away from the paywall.
      onPurchaseResult: (result, entitlements) {
        switch (result.outcome) {
          case PurchaseOutcome.success:
            unawaited(reportResultToWebView('success'));
          case PurchaseOutcome.pending:
            unawaited(reportResultToWebView('cancel', 'Waiting for approval.'));
          case PurchaseOutcome.cancelled:
            unawaited(reportResultToWebView('cancel'));
        }
        widget.onPurchaseResult?.call(result, entitlements);
      },
      onPurchaseError: (error) {
        unawaited(reportResultToWebView('fail'));
        widget.onPurchaseError?.call(error);
      },
      onDismiss: widget.onDismiss,
    );

    final html = PaywallShellAssembler.assemble(
      bodyHtml: snapshot.html,
      platformScriptJs: widget.platformScriptJs,
    );

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Transparent so the WebView's own blank first paint is never a white
      // flash: while hidden there is nothing to see through to but the host
      // background, and the paywall html paints its own background once loaded.
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final decision = await runtime.handleNavigationRequest(request.url);
            return decision == PaywallNavigationDecision.prevent
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
          // Price injection runs JS against the page's own global, so it must
          // wait for the inline <script> to have actually executed -- firing
          // it right after loadHtmlString's Future completes (which only
          // means the load was *initiated*) races a cold WebView's first
          // paint and can silently miss, especially since a cached StoreKit
          // price can resolve faster than that paint
          onPageFinished: (_) {
            unawaited(runtime.onSnapshotLoaded(resolvedSnapshot));
            // The whole document (including external resources) has loaded, so
            // reveal if the cap below has not already. setPrices reveals sooner
            // once prices land.
            _reveal();
          },
        ),
      )
      ..loadHtmlString(html);

    if (!mounted) return;
    setState(() {
      _controller = controller;
      _ready = true;
    });

    // Hang guard only. The paywall is revealed when its content has actually
    // painted (onPageFinished) or its prices land (setPrices) -- never on a
    // fixed delay, because the WebView is transparent while hidden, so
    // revealing it before it has painted shows through to the host background
    // (a black gap) until paint catches up. This timer exists solely so a
    // WebView that never finishes (load hung, no network) still reveals rather
    // than spinning forever; it is deliberately far longer than any real load.
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(seconds: 8), _reveal);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // The WebView is built as soon as the controller exists but stays hidden
    // (Opacity 0, transparent background) beneath the loading indicator until
    // `_visible` flips. This loads and paints it off-screen, so revealing it
    // is a single cut from spinner to a fully-formed, priced paywall rather
    // than the white-flash -> half-ui -> full-ui sequence a plain mount shows.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_ready && controller != null)
          Opacity(
            opacity: _visible ? 1 : 0,
            child: WebViewWidget(controller: controller),
          ),
        if (!_visible) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
