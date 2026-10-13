import { parseCoproductAction } from './coproductAction';
import type { CoproductClient } from './coproductClient';
import { LocalProgressStore } from './localProgressStore';
import type { OnboardingFlowGraph } from './models/onboardingFlowGraph';
import { defaultRequestPermission } from './permissions';
import type { PermissionRequestFn } from './permissions';
import { assembleShell } from './shellAssembler';

export type { PermissionRequestFn };

export type FlowNavigationDecision = 'prevent' | 'navigate';

export type EventCallback = (
  event: string,
  screenId: string,
  answers: Record<string, string[]>
) => Promise<void>;
export type PermissionCallback = (permission: string) => Promise<void>;
export type OpenUrlCallback = (url: string) => Promise<void>;
export type PaywallCallback = (paywallId: string) => Promise<void>;
export type NativeOperationCallback = (
  operation: string,
  params: Record<string, string>
) => Promise<Record<string, string>>;
export type ResolveRequestFn = (
  requestId: string,
  response: Record<string, string>
) => Promise<void>;

// Owns everything native does in the flow-runtime split: assembling the
// shell, intercepting coproduct-action: navigation, persisting progress
// before the host callback fires, and dispatching native-capability
// actions. Deliberately does not construct or hold a WebView instance
// itself, so this logic stays unit-testable without a real WebView.
// Mirrors sdks/flutter/coproduct/lib/src/onboarding/flow_runtime.dart.
export class FlowRuntime {
  private readonly client: CoproductClient;
  private readonly progressStore: LocalProgressStore;
  private readonly flowId?: string;
  private readonly flowVersion?: number;
  private readonly onEvent?: EventCallback;
  private readonly onRequestPermission?: PermissionCallback;
  private readonly onOpenUrl?: OpenUrlCallback;
  private readonly onShowPaywall?: PaywallCallback;
  private readonly onNativeOperation?: NativeOperationCallback;
  private readonly requestPermissionFn: PermissionRequestFn;
  private resolveRequestFn?: ResolveRequestFn;

  constructor(args: {
    client: CoproductClient;
    progressStore: LocalProgressStore;
    flowId?: string;
    flowVersion?: number;
    onEvent?: EventCallback;
    onRequestPermission?: PermissionCallback;
    onOpenUrl?: OpenUrlCallback;
    onShowPaywall?: PaywallCallback;
    onNativeOperation?: NativeOperationCallback;
    requestPermission?: PermissionRequestFn;
  }) {
    this.client = args.client;
    this.progressStore = args.progressStore;
    this.flowId = args.flowId;
    this.flowVersion = args.flowVersion;
    this.onEvent = args.onEvent;
    this.onRequestPermission = args.onRequestPermission;
    this.onOpenUrl = args.onOpenUrl;
    this.onShowPaywall = args.onShowPaywall;
    this.onNativeOperation = args.onNativeOperation;
    this.requestPermissionFn =
      args.requestPermission ?? defaultRequestPermission;
  }

  // Wired by CoproductOnboardingFlow once its WebView ref exists, so this
  // class never has to import react-native-webview or hold a ref itself.
  attachResolver(resolveRequest: ResolveRequestFn): void {
    this.resolveRequestFn = resolveRequest;
  }

  buildShellHtml(args: {
    graph: OnboardingFlowGraph;
    flowId: string;
    initialScreenId?: string;
    initialAnswers?: Record<string, string[]>;
    platformScriptJs?: string;
  }): string {
    const initialScreenId =
      args.initialScreenId != null && args.initialScreenId.length > 0
        ? args.initialScreenId
        : args.graph.startScreenId;
    return assembleShell({
      graph: args.graph,
      sdkContextAttributes: this.client.sdkContextAttributes,
      sdkContextSegmentKeys: this.client.sdkContextSegmentKeys,
      initialAnswers: args.initialAnswers ?? {},
      initialScreenId,
      platformScriptJs: args.platformScriptJs ?? '',
    });
  }

  async handleNavigationRequest(url: string): Promise<FlowNavigationDecision> {
    const action = parseCoproductAction(url);
    if (action == null) return 'navigate';

    switch (action.type) {
      case 'track':
        if (this.flowId != null && this.flowVersion != null) {
          await this.progressStore.save({
            flowId: this.flowId,
            version: this.flowVersion,
            screenId: action.screenId,
            answers: action.answers,
          });
        }
        await this.onEvent?.(action.event, action.screenId, action.answers);
        break;
      case 'requestPermission':
        await this.onRequestPermission?.(action.permission);
        break;
      case 'openUrl':
        await this.onOpenUrl?.(action.url);
        break;
      case 'showPaywall':
        await this.onShowPaywall?.(action.paywallId);
        break;
      case 'request':
        // Deliberately not awaited: the decision below must return
        // immediately without waiting for a slow native operation or
        // permission prompt to resolve, matching Dart's unawaited(...).
        // eslint-disable-next-line no-void
        void this.handleRequestAction(action);
        break;
      case 'dismiss':
      case 'complete':
        // dismiss/complete are reported via the track action that precedes
        // them (flow_dismissed / flow_completed) -- nothing further to do here
        break;
    }

    return 'prevent';
  }

  private async handleRequestAction(action: {
    operation: string;
    requestId: string;
    params: Record<string, string>;
  }): Promise<void> {
    const response = await this.computeRequestResponse(action);
    await this.resolveRequestFn?.(action.requestId, response);
  }

  private async computeRequestResponse(action: {
    operation: string;
    params: Record<string, string>;
  }): Promise<Record<string, string>> {
    if (action.operation === 'requestPermission') {
      try {
        return await this.requestPermissionFn(action.params.permission ?? '');
      } catch (error) {
        return { status: 'error', message: String(error) };
      }
    }
    const handler = this.onNativeOperation;
    if (handler == null) {
      return {
        status: 'error',
        message: `No handler registered for operation "${action.operation}"`,
      };
    }
    try {
      return await handler(action.operation, action.params);
    } catch (error) {
      return { status: 'error', message: String(error) };
    }
  }
}
