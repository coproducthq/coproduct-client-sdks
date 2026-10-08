import 'dart:async' show unawaited;
import 'dart:convert';

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

/// Thrown through [CoproductPaywall.onLoadError] when a paywall can't be
/// fetched -- not found for this environment, or the request itself failed.
class PaywallLoadError {
  final String message;
  const PaywallLoadError(this.message);
}

/// Renders and drives one resolved paywall: fetches it, loads its html into
/// a WebView, resolves and injects live StoreKit2 prices, and completes a
/// purchase or restore when the user taps a cta. [paywallId] is resolved
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
  /// StoreKit2 MethodChannel bridge.
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
    'packages/coproduct_paywall/assets/paywall-platform-script.js',
  );

  @override
  State<CoproductPaywall> createState() => _CoproductPaywallState();
}

class _CoproductPaywallState extends State<CoproductPaywall> {
  WebViewController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final client =
        widget.client ??
        HttpPaywallClient(sdkKey: widget.sdkKey, envSlug: widget.envSlug);
    final bridge = widget.bridge ?? const MethodChannelPaywallBridge();

    PaywallSnapshot? snapshot;
    try {
      snapshot = await client.fetchPaywall(widget.paywallId);
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

    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: widget.appUserId,
      setPrices: (prices) async {
        try {
          await _controller?.runJavaScript(
            'window.__coproductSetPrices__(${jsonEncode(prices)})',
          );
        } catch (_) {
          // The WebView may already be torn down by the time prices
          // resolve -- nothing to do
        }
      },
      onPurchaseResult: widget.onPurchaseResult,
      onPurchaseError: widget.onPurchaseError,
      onDismiss: widget.onDismiss,
    );

    final html = PaywallShellAssembler.assemble(
      bodyHtml: snapshot.html,
      platformScriptJs: widget.platformScriptJs,
    );

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
          },
        ),
      )
      ..loadHtmlString(html);

    if (!mounted) return;
    setState(() {
      _controller = controller;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) return const SizedBox.shrink();
    return WebViewWidget(controller: _controller!);
  }
}
