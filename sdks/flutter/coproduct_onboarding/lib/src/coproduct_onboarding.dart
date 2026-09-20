import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import 'coproduct_client.dart';
import 'flow_runtime.dart';
import 'local_progress_store.dart';
import 'splash_screen_widget.dart';

/// Renders and drives one onboarding flow, resolved from [flagKey] via
/// [client] exactly the way any other flag resolves. Shows
/// [SplashScreenWidget] until the shell is assembled and the WebView has
/// loaded it.
class CoproductOnboardingFlow extends StatefulWidget {
  final String flagKey;
  final CoproductClient client;
  final String fallbackSplashAssetPath;
  final EventCallback? onEvent;
  final PermissionCallback? onRequestPermission;
  final OpenUrlCallback? onOpenUrl;
  final PaywallCallback? onShowPaywall;
  final String platformScriptJs;

  const CoproductOnboardingFlow({
    super.key,
    required this.flagKey,
    required this.client,
    required this.platformScriptJs,
    this.fallbackSplashAssetPath = 'packages/coproduct_onboarding/assets/coproduct_fallback_splash.png',
    this.onEvent,
    this.onRequestPermission,
    this.onOpenUrl,
    this.onShowPaywall,
  });

  /// Loads the platform script bundled as this package's own asset. A host
  /// app calls this once and passes the result into [platformScriptJs]
  /// rather than knowing the asset path itself.
  static Future<String> loadPlatformScript() =>
      rootBundle.loadString('packages/coproduct_onboarding/assets/platform-script.js');

  @override
  State<CoproductOnboardingFlow> createState() => _CoproductOnboardingFlowState();
}

class _CoproductOnboardingFlowState extends State<CoproductOnboardingFlow> {
  WebViewController? _controller;
  bool _ready = false;
  String? _splashImageUrl;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final flowId = widget.client.resolveStringFlag(widget.flagKey);
    if (flowId == null) return; // no flow resolved for this device — caller decides the fallback UI

    final graph = widget.client.onboardingFlowGraph(flowId);
    if (graph == null) return;

    if (mounted) setState(() { _splashImageUrl = graph.splashImage; });

    final progressStore = LocalProgressStore();
    final progress = await progressStore.load(flowId: flowId);

    final runtime = FlowRuntime(
      client: widget.client,
      progressStore: progressStore,
      flowId: flowId,
      flowVersion: progress?.version ?? 1,
      onEvent: widget.onEvent,
      onRequestPermission: widget.onRequestPermission,
      onOpenUrl: widget.onOpenUrl,
      onShowPaywall: widget.onShowPaywall,
    );

    final html = runtime.buildShellHtml(
      graph: graph,
      flowId: flowId,
      // Resume where you left off: a device with local persistence resumes
      // on whichever screen it started on, not from startScreenId
      initialScreenId: progress?.screenId ?? graph.startScreenId,
      initialAnswers: progress?.answers ?? const {},
      platformScriptJs: widget.platformScriptJs,
    );

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) async {
          final decision = await runtime.handleNavigationRequest(request.url);
          return decision == FlowNavigationDecision.prevent
              ? NavigationDecision.prevent
              : NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(html);

    if (!mounted) return;
    setState(() {
      _controller = controller;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return SplashScreenWidget(splashImageUrl: _splashImageUrl, fallbackAssetPath: widget.fallbackSplashAssetPath);
    }
    return WebViewWidget(controller: _controller!);
  }
}
