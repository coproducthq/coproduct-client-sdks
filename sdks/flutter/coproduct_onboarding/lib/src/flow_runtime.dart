import 'coproduct_action.dart';
import 'coproduct_client.dart';
import 'local_progress_store.dart';
import 'models/onboarding_flow_graph.dart';
import 'shell_assembler.dart';

/// A native-side decision about a WebView navigation request. Deliberately
/// not webview_flutter's own NavigationDecision type — this class stays
/// testable without importing a plugin that needs a real platform channel.
/// The public entry point (CoproductOnboardingFlow) maps this onto the real
/// one at its single call site
enum FlowNavigationDecision { prevent, navigate }

typedef EventCallback = Future<void> Function(String event, String screenId, Map<String, List<String>> answers);
typedef PermissionCallback = Future<void> Function(String permission);
typedef OpenUrlCallback = Future<void> Function(String url);
typedef PaywallCallback = Future<void> Function(String paywallId);

/// Owns everything native does in the flow-runtime split: assembling the
/// shell, intercepting coproduct-action: navigation, persisting progress
/// before the host callback fires, and dispatching native-capability
/// actions. Deliberately does not construct or hold a WebViewController
/// itself, so this logic stays unit-testable without a real WebView
class FlowRuntime {
  final CoproductClient client;
  final LocalProgressStore progressStore;
  final String? flowId;
  final int? flowVersion;
  final EventCallback? onEvent;
  final PermissionCallback? onRequestPermission;
  final OpenUrlCallback? onOpenUrl;
  final PaywallCallback? onShowPaywall;

  FlowRuntime({
    required this.client,
    required this.progressStore,
    this.flowId,
    this.flowVersion,
    this.onEvent,
    this.onRequestPermission,
    this.onOpenUrl,
    this.onShowPaywall,
  });

  String buildShellHtml({
    required OnboardingFlowGraph graph,
    required String flowId,
    String initialScreenId = '',
    Map<String, List<String>> initialAnswers = const {},
    String platformScriptJs = '',
  }) {
    return ShellAssembler.assemble(
      graph: graph,
      sdkContextAttributes: client.sdkContextAttributes,
      sdkContextSegmentKeys: client.sdkContextSegmentKeys,
      initialAnswers: initialAnswers,
      initialScreenId: initialScreenId.isEmpty ? graph.startScreenId : initialScreenId,
      platformScriptJs: platformScriptJs,
    );
  }

  Future<FlowNavigationDecision> handleNavigationRequest(String url) async {
    final action = CoproductAction.parse(url);
    if (action == null) return FlowNavigationDecision.navigate;

    switch (action) {
      case TrackAction():
        if (flowId != null && flowVersion != null) {
          await progressStore.save(
            flowId: flowId!,
            version: flowVersion!,
            screenId: action.screenId,
            answers: action.answers,
          );
        }
        await onEvent?.call(action.event, action.screenId, action.answers);
      case RequestPermissionAction():
        await onRequestPermission?.call(action.permission);
      case OpenUrlAction():
        await onOpenUrl?.call(action.url);
      case ShowPaywallAction():
        await onShowPaywall?.call(action.paywallId);
      case DismissAction():
      case CompleteAction():
        // dismiss/complete are reported via the track action that precedes
        // them (flow_dismissed / flow_completed) — nothing further to do here
        break;
    }

    return FlowNavigationDecision.prevent;
  }
}
