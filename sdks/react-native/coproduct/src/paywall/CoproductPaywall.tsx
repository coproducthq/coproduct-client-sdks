import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { WebView } from 'react-native-webview';
import { HttpPaywallClient } from './httpPaywallClient';
import { IapPaywallBridge } from './iapPaywallBridge';
import type { PaywallSnapshot } from './models/paywallSnapshot';
import type { NativePaywallBridge } from './nativePaywallBridge';
import type { PaywallClient } from './paywallClient';
import {
  PaywallRuntime,
  type PurchaseErrorCallback,
  type PurchaseResultCallback,
} from './paywallRuntime';
import { assemblePaywallShell } from './paywallShellAssembler';
import { platformScriptJs as bundledPlatformScriptJs } from './platformScript.generated';

export interface PaywallLoadError {
  message: string;
}

export interface CoproductPaywallProps {
  paywallId: string;
  appUserId: string;
  sdkKey: string;
  platformScriptJs: string;
  envSlug?: string;
  onPurchaseResult?: PurchaseResultCallback;
  onPurchaseError?: PurchaseErrorCallback;
  onLoadError?: (error: PaywallLoadError) => void;
  onDismiss?: () => void;
  client?: PaywallClient;
  bridge?: NativePaywallBridge;
}

// Renders and drives one resolved paywall: fetches it, loads its html into a
// WebView, resolves and injects live StoreKit2 prices, and completes a
// purchase or restore when the user taps a cta. Mirrors
// sdks/flutter/coproduct/lib/src/paywall/coproduct_paywall.dart.
export function CoproductPaywall(props: CoproductPaywallProps) {
  const {
    paywallId,
    appUserId,
    sdkKey,
    platformScriptJs,
    envSlug,
    onPurchaseResult,
    onPurchaseError,
    onLoadError,
    onDismiss,
    client: clientOverride,
    bridge: bridgeOverride,
  } = props;
  const [html, setHtml] = useState<string | undefined>(undefined);
  const runtimeRef = useRef<PaywallRuntime | undefined>(undefined);
  const webViewRef = useRef<WebView | null>(null);
  const loadedSnapshotRef = useRef<PaywallSnapshot | undefined>(undefined);

  const boot = useCallback(async (): Promise<void> => {
    const client = clientOverride ?? new HttpPaywallClient({ sdkKey, envSlug });
    const bridge = bridgeOverride ?? new IapPaywallBridge();

    let snapshot: PaywallSnapshot | undefined;
    try {
      snapshot = await client.fetchPaywall(paywallId);
    } catch (error) {
      onLoadError?.({ message: String(error) });
      return;
    }
    if (snapshot == null) {
      onLoadError?.({ message: 'Paywall not found for this environment.' });
      return;
    }

    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId,
      setPrices: async (prices) => {
        try {
          webViewRef.current?.injectJavaScript(
            `window.__coproductSetPrices__(${JSON.stringify(prices)}); true;`
          );
        } catch {
          // The WebView may already be torn down by the time prices resolve
        }
      },
      onPurchaseResult,
      onPurchaseError,
      onDismiss,
    });
    runtimeRef.current = runtime;
    loadedSnapshotRef.current = snapshot;

    const shellHtml = assemblePaywallShell({
      bodyHtml: snapshot.html,
      platformScriptJs,
    });
    setHtml(shellHtml);
  }, [
    appUserId,
    bridgeOverride,
    clientOverride,
    envSlug,
    onDismiss,
    onLoadError,
    onPurchaseError,
    onPurchaseResult,
    paywallId,
    platformScriptJs,
    sdkKey,
  ]);

  useEffect(() => {
    // Deliberately not awaited: a mount effect cannot be async, and the
    // boot sequence's own state updates (setHtml) are what the render
    // path reacts to.
    // eslint-disable-next-line no-void
    void boot();
    // Boots once per mount, matching Flutter's one-shot initState boot.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (html == null) {
    return (
      <View style={styles.splashContainer}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <View style={styles.flexContainer}>
      {/* The explicit <object> type argument is load-bearing -- see
          CoproductOnboardingFlow.tsx's identical comment for why. */}
      <WebView<object>
        ref={webViewRef}
        originWhitelist={['*']}
        source={{ html }}
        onLoadEnd={() => {
          // Price injection runs JS against the page's own global, so it
          // must wait for the inline <script> to have actually executed --
          // firing right after the shell is assembled (before the WebView
          // has painted) races a cold WebView's first paint and can
          // silently miss, especially since a cached StoreKit price can
          // resolve faster than that paint. Mirrors Flutter's
          // onPageFinished placement exactly.
          const snapshot = loadedSnapshotRef.current;
          if (snapshot != null) {
            // eslint-disable-next-line no-void
            void runtimeRef.current?.onSnapshotLoaded(snapshot);
          }
        }}
        onShouldStartLoadWithRequest={(request) => {
          const runtime = runtimeRef.current;
          const isAction = request.url.startsWith('coproduct-action:');
          if (isAction && runtime != null) {
            // eslint-disable-next-line no-void
            void runtime.handleNavigationRequest(request.url);
          }
          return !isAction;
        }}
      />
    </View>
  );
}

// Loads the platform script bundled as this package's own generated source.
// Mirrors CoproductOnboardingFlow.loadPlatformScript -- stays async-shaped
// for call-site parity with Flutter, even though this implementation does
// zero I/O.
CoproductPaywall.loadPlatformScript = async (): Promise<string> =>
  bundledPlatformScriptJs;

const styles = StyleSheet.create({
  splashContainer: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  flexContainer: { flex: 1 },
});
