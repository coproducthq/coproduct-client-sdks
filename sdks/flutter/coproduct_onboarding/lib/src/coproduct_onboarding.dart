import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import 'coproduct_client.dart';
import 'debug_flow_drawer.dart';
import 'flow_runtime.dart';
import 'local_progress_store.dart';
import 'models/onboarding_flow_graph.dart';
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

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// Rebuilds the shell from whatever the client currently resolves --
  /// [clearProgress] discards saved progress first (a debug "restart flow"),
  /// otherwise this forces a fresh server poll before resuming on the same
  /// screen (a debug "refresh"), so a content edit is guaranteed visible
  /// immediately rather than only once the base SDK's own background poll
  /// happens to land
  Future<void> _rebuild({required bool clearProgress}) async {
    if (clearProgress) {
      final flowId = widget.client.resolveStringFlag(widget.flagKey);
      if (flowId != null) await LocalProgressStore().clear(flowId: flowId);
    } else {
      await widget.client.refresh();
    }
    if (mounted) setState(() { _ready = false; _controller = null; });
    await _boot();
  }

  Future<void> _boot() async {
    final flowId = widget.client.resolveStringFlag(widget.flagKey);
    if (flowId == null) return; // no flow resolved for this device — caller decides the fallback UI

    // Independent of flag resolution above: the flag only ever carried
    // flowId, this is a live fetch of that flow's content, pinned to
    // whichever environment this device is in. A failed/unresolvable fetch
    // leaves _ready false -- same fallback UI as no flow resolved at all,
    // caller decides what that means
    final OnboardingFlowGraph? graph;
    try {
      graph = await widget.client.fetchOnboardingFlow(flowId);
    } catch (_) {
      return;
    }
    if (graph == null) return;

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
    final content = !_ready || _controller == null
        ? SplashScreenWidget(fallbackAssetPath: widget.fallbackSplashAssetPath)
        : WebViewWidget(controller: _controller!);

    // Debug-only: lets an author see a content edit made through the
    // coproduct MCP tools without a full app kill/relaunch. kDebugMode means
    // this (and DebugFlowDrawer entirely) is compiled out of a release build
    if (!kDebugMode) return content;
    return Stack(
      children: [
        content,
        DebugFlowDrawer(
          onRestartFlow: () => _rebuild(clearProgress: true),
          onRefresh: () => _rebuild(clearProgress: false),
        ),
      ],
    );
  }
}
