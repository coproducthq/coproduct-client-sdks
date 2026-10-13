import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { WebView } from 'react-native-webview';
import type { CoproductClient } from './coproductClient';
import { DebugFlowDrawer } from './debugFlowDrawer';
import {
  FlowRuntime,
  type EventCallback,
  type NativeOperationCallback,
  type OpenUrlCallback,
  type PaywallCallback,
  type PermissionCallback,
} from './flowRuntime';
import { LocalProgressStore } from './localProgressStore';
import { platformScriptJs as bundledPlatformScriptJs } from './platformScript.generated';

export interface CoproductOnboardingFlowProps {
  flagKey: string;
  client: CoproductClient;
  platformScriptJs: string;
  fallbackSplash?: React.ReactNode;
  onEvent?: EventCallback;
  onRequestPermission?: PermissionCallback;
  onOpenUrl?: OpenUrlCallback;
  onShowPaywall?: PaywallCallback;
  onNativeOperation?: NativeOperationCallback;
}

// Renders and drives one onboarding flow, resolved from flagKey via client
// exactly the way any other flag resolves. Shows fallbackSplash (a plain
// ActivityIndicator by default) until the shell is assembled and the
// WebView has loaded it. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/coproduct_onboarding.dart.
export function CoproductOnboardingFlow(props: CoproductOnboardingFlowProps) {
  const {
    flagKey,
    client,
    platformScriptJs,
    fallbackSplash,
    onEvent,
    onRequestPermission,
    onOpenUrl,
    onShowPaywall,
    onNativeOperation,
  } = props;
  const [html, setHtml] = useState<string | undefined>(undefined);
  const runtimeRef = useRef<FlowRuntime | undefined>(undefined);
  const webViewRef = useRef<WebView | null>(null);
  const progressStore = useRef(new LocalProgressStore()).current;

  const boot = useCallback(async (): Promise<void> => {
    const flowId = client.resolveStringFlag(flagKey);
    if (flowId == null) return; // no flow resolved -- caller decides the fallback UI

    let graph;
    try {
      graph = await client.fetchOnboardingFlow(flowId);
    } catch {
      return;
    }
    if (graph == null) return;

    const progress = await progressStore.load({ flowId });

    const runtime = new FlowRuntime({
      client,
      progressStore,
      flowId,
      flowVersion: progress?.version ?? 1,
      onEvent,
      onRequestPermission,
      onOpenUrl,
      onShowPaywall,
      onNativeOperation,
    });
    runtimeRef.current = runtime;

    const shellHtml = runtime.buildShellHtml({
      graph,
      flowId,
      initialScreenId: progress?.screenId ?? graph.startScreenId,
      initialAnswers: progress?.answers ?? {},
      platformScriptJs,
    });

    runtime.attachResolver(async (requestId, response) => {
      try {
        webViewRef.current?.injectJavaScript(
          `window.__coproductResolveRequest__(${JSON.stringify(requestId)}, ${JSON.stringify(response)}); true;`
        );
      } catch {
        // The WebView may already be torn down (user navigated away, debug
        // restart) by the time a slow request resolves -- nothing to do
      }
    });

    setHtml(shellHtml);
  }, [
    client,
    flagKey,
    platformScriptJs,
    onEvent,
    onRequestPermission,
    onOpenUrl,
    onShowPaywall,
    onNativeOperation,
    progressStore,
  ]);

  const rebuild = useCallback(
    async (args: { clearProgress: boolean }): Promise<void> => {
      if (args.clearProgress) {
        const flowId = client.resolveStringFlag(flagKey);
        if (flowId != null) await progressStore.clear({ flowId });
      } else {
        await client.refresh();
      }
      setHtml(undefined);
      runtimeRef.current = undefined;
      await boot();
    },
    [boot, client, flagKey, progressStore]
  );

  useEffect(() => {
    // Deliberately not awaited: a mount effect cannot be async, and the
    // boot sequence's own state updates (setHtml) are what the render
    // path reacts to.
    // eslint-disable-next-line no-void
    void boot();
    // Boots once per mount, matching Flutter's one-shot initState boot --
    // not a continuous re-render loop keyed on every prop change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (html == null) {
    return (
      <View style={styles.splashContainer}>
        {fallbackSplash ?? <ActivityIndicator />}
      </View>
    );
  }

  return (
    <View style={styles.flexContainer}>
      {/* The explicit <object> type argument is load-bearing: react-native-webview's
          .d.ts declares `class WebView<P = undefined> extends Component<WebViewProps & P>`.
          Used bare as <WebView ... /> (no type argument), P defaults to undefined, and
          WebViewProps & undefined collapses to `never` under this project's TypeScript
          version, breaking every prop below. Confirmed empirically: removing this
          annotation reproduces a "props: never" overload error from tsc. */}
      <WebView<object>
        ref={webViewRef}
        originWhitelist={['*']}
        source={{ html }}
        onShouldStartLoadWithRequest={(request) => {
          const runtime = runtimeRef.current;
          const isAction = request.url.startsWith('coproduct-action:');
          // parseCoproductAction's own first line rejects any URL not
          // carrying this prefix, synchronously -- so the decision here is
          // provably identical to awaiting runtime.handleNavigationRequest's
          // resolved value, without blocking this synchronous callback on
          // it. The real dispatch work still runs via the fire-and-forget
          // call below; react-native-webview requires a synchronous
          // return, unlike Flutter's NavigationDelegate, which accepts a
          // Future.
          if (isAction && runtime != null) {
            // eslint-disable-next-line no-void
            void runtime.handleNavigationRequest(request.url);
          }
          return !isAction;
        }}
      />
      {__DEV__ ? (
        <DebugFlowDrawer
          onRestartFlow={() => rebuild({ clearProgress: true })}
          onRefresh={() => rebuild({ clearProgress: false })}
        />
      ) : null}
    </View>
  );
}

// Loads the platform script bundled as this package's own generated
// source. A host app calls this once and passes the result into
// platformScriptJs rather than knowing the bundling mechanism itself.
// Stays async-shaped (Promise<string>) for call-site parity with
// Flutter's loadPlatformScript, even though this implementation does zero
// I/O. Attaching this to a `function` declaration (not an arrow const)
// lets TypeScript infer the augmented type from this same module, so
// callers see CoproductOnboardingFlow.loadPlatformScript without a
// separate type declaration.
CoproductOnboardingFlow.loadPlatformScript = async (): Promise<string> =>
  bundledPlatformScriptJs;

const styles = StyleSheet.create({
  splashContainer: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  flexContainer: { flex: 1 },
});
